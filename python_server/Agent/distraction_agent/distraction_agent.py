from pydantic import BaseModel
from agents import Agent, ModelSettings, RunContextWrapper, TResponseInputItem, Runner, RunConfig, trace
from openai.types.shared.reasoning import Reasoning
import json

import Agent.distraction_agent.agent_instructions as agent_instructions 


class DistractionDeterminationSchema(BaseModel):
  student_status: str
  page_relevance: str
  reasoning_summary: str


class ConfusionRecordingSchema(BaseModel):
  topic: str
  summary: str
  missed_content: str


class BehindRecordingSchema(BaseModel):
  missed_content: str


distraction_determination = Agent(
  name="Distraction Determination",
  instructions=agent_instructions.Distraction_Determination,
  model="gpt-5-nano",
  output_type=DistractionDeterminationSchema,
  model_settings=ModelSettings(
    store=True,
    reasoning=Reasoning(
      effort="medium",
      summary="auto"
    )
  )
)


confusion_recording = Agent(
  name=" Confusion Recording",
  instructions=agent_instructions.Confusion_Recording,
  model="gpt-5.5",
  output_type=ConfusionRecordingSchema,
  model_settings=ModelSettings(
    store=True,
    reasoning=Reasoning(
      effort="high",
      summary="auto"
    )
  )
)

behind_recording = Agent(
  name="Behind Recording",
  instructions=agent_instructions.Behind_Recording,
  model="gpt-5.5",
  output_type=BehindRecordingSchema,
  model_settings=ModelSettings(
    store=True,
    reasoning=Reasoning(
      effort="high",
      summary="auto"
    )
  )
)


class WorkflowInput(BaseModel):
  student_current_page: int
  student_current_page_content: str
  teacher_current_page: int
  teacher_current_page_content: str
  recent_transcript: str
  student_page_history: list[tuple[int, str]]  # page number to time stamp
  previous_memory: list[str]
  


# Main code entrypoint
async def detraction_detect(workflow_input: WorkflowInput):
  with trace("New agent"):
    #initialize
    state = {
      "student_status": None,
      "page_relevance": None,
      "reasoning_summary": None,
      "student_current_page": None,
      "student_current_page_content": None,
      "teacher_current_page": None,
      "teacher_current_page_content": None,
      "recent_transcript": None,
      "student_page_history": None,
      "previous_memory": None
    }
    workflow = workflow_input.model_dump()

    #set state
    state["student_current_page"] = workflow["student_current_page"]
    state["student_current_page_content"] = workflow["student_current_page_content"]
    state["teacher_current_page"] = workflow["teacher_current_page"]
    state["teacher_current_page_content"] = workflow["teacher_current_page_content"]
    state["recent_transcript"] = workflow["recent_transcript"]
    state["student_page_history"] = workflow["student_page_history"]
    state["previous_memory"] = workflow["previous_memory"]

    #set inputs
    inputs: list[TResponseInputItem] = [
        {
            "role": "user",
            "content": [
                {
                    "type": "input_text",
                    "text": json.dumps(
                        {
                            "student_current_page": state["student_current_page"],
                            "student_current_page_content": state["student_current_page_content"],
                            "teacher_current_page": state["teacher_current_page"],
                            "teacher_current_page_content": state["teacher_current_page_content"],
                            "recent_transcript": state["recent_transcript"],
                            "student_page_history": state["student_page_history"],
                            "previous_memory": state["previous_memory"],
                        },
                        ensure_ascii=False,
                        indent=2,
                    ),
                }
            ],
        }
    ]

    #distraction determination agent
    distraction_determination_result_temp = await Runner.run(
      distraction_determination,
      input=[
        *inputs
      ],
      run_config=RunConfig(trace_metadata={
        "__trace_source__": "agent-builder",
        "workflow_id": "wf_6a0970a385508190b51c1e4a0b75d78f03c95ccbe6c624b6"
      }),
      max_turns=2
    )
    
    #result parsing and state updating
    distraction_determination_result = {
      "output_text": distraction_determination_result_temp.final_output.json(),
      "output_parsed": distraction_determination_result_temp.final_output.model_dump()
    }
    state["student_status"] = distraction_determination_result["output_parsed"]["student_status"]
    state["page_relevance"] = distraction_determination_result["output_parsed"]["page_relevance"]
    state["reasoning_summary"] = distraction_determination_result["output_parsed"]["reasoning_summary"]

    #change state to input for next agent
    state_to_input : list[TResponseInputItem] = [
        {
            "role": "user",
            "content": [
                {
                    "type": "input_text",
                    "text": json.dumps(state, ensure_ascii=False, indent=2),
                }
            ],
        }
    ]

    # Based on the student status, decide the next steps
    if distraction_determination_result["output_parsed"]["student_status"] == "following":
      end_result = {
        "actions": [
            "do_nothing"
        ]
      }
      return end_result
    
    elif distraction_determination_result["output_parsed"]["student_status"] == "confused":
      confusion_recording_result_temp = await Runner.run(
        confusion_recording,
        input=[
          *state_to_input
        ],
        run_config=RunConfig(trace_metadata={
          "__trace_source__": "agent-builder",
          "workflow_id": "wf_6a0970a385508190b51c1e4a0b75d78f03c95ccbe6c624b6"
        }),
      )
      confusion_recording_result = {
        "output_text": confusion_recording_result_temp.final_output.json(),
        "output_parsed": confusion_recording_result_temp.final_output.model_dump()
      }
      end_result = {
        "actions": [
          "update_missed_content",
          "update_confused_content"

        ],
        "missed_content": confusion_recording_result["output_parsed"]["missed_content"],
        "confused_content_topic": confusion_recording_result["output_parsed"]["topic"],
        "confused_content_summary": confusion_recording_result["output_parsed"]["summary"]
      }
      return end_result
    
    elif distraction_determination_result["output_parsed"]["student_status"] == "behind":
      behind_recording_result_temp = await Runner.run(
        behind_recording,
        input=[
          *state_to_input
        ],
        run_config=RunConfig(trace_metadata={
          "__trace_source__": "agent-builder",
          "workflow_id": "wf_6a0970a385508190b51c1e4a0b75d78f03c95ccbe6c624b6"
        }),
      )
      behind_recording_result = {
        "output_text": behind_recording_result_temp.final_output.json(),
        "output_parsed": behind_recording_result_temp.final_output.model_dump()
      }
      end_result = {
        "actions": [
          "update_missed_content"

        ],
        "missed_content": behind_recording_result["output_parsed"]["missed_content"]
      }
      return end_result
    
    elif distraction_determination_result["output_parsed"]["student_status"] == "distracted":
      end_result = {
        "actions": [
            "call_distraction_recovery"
        ]
      }
      return end_result
    
    else:
      end_result = {
        "actions": [
          "invalid"

        ]}
      return end_result
