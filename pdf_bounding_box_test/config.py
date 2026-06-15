# config.py
# Configuration file for the Segment Anything, OpenCV, & Gemini Bounding Box Pipeline

# 1. Pipeline Inputs and Outputs
# Original diagram image to run the pipeline on
import os

INPUT_IMAGE = "Chapter_4_1 _page-0020.jpg"

# 2. OpenAI Configuration (1_bounding_box_choice)
OPENAI_API_KEY = os.environ.get(
    "OPENAI_API_KEY"
)  # Retrieve key from OS environment variable
OPENAI_MODEL = "gpt-5-mini"

OPENAI_PROMPT_FILE = "openai_prompt.txt"
_config_dir = os.path.dirname(os.path.abspath(__file__))
_prompt_path = os.path.join(_config_dir, OPENAI_PROMPT_FILE)
if os.path.exists(_prompt_path):
    with open(_prompt_path, "r", encoding="utf-8") as f:
        OPENAI_PROMPT = f.read().strip()
else:
    OPENAI_PROMPT = (
        "i'm creating an ai agent. the tools i have are bounding_boxes and text corresponding to each bounding_box. "
        "imagine a scenario where a student got lost in class and found that the teacher is at this particular slide. "
        "what would you mark with the bounding box and text to help the student catch up immediately. "
        "each text can relate to more than 1 bounding boxes"
        "the text should be 10 at most."
        "make sure that the text you wrote have something to do with a specific item on the slide that the bounding box can bound. don't just write a random overview."
    )
GPT_OUTPUT_JSON = "1_bounding_box_choice/gpt_output.json"

# 3. OpenCV Segmentation Configuration (2_OpenCV)
sidebar_width = 300  # Not used but defined
OPENCV_OUTPUT_IMAGE = "2_OpenCV/annotated_datapath.jpg"
OPENCV_OUTPUT_JSON = "2_OpenCV/opencv_region_coordinates.json"

# 4. OpenCV Morph Segmentation Configuration (2_OpenCV_morph)
MORPH_OUTPUT_IMAGE = "2_OpenCV_morph/morph_numbered_diagram.jpg"
MORPH_OUTPUT_JSON = "2_OpenCV_morph/morph_region_coordinates.json"

# 5. SAM Segmentation Configuration (2_SAM)
SAM_OUTPUT_IMAGE = "2_SAM/sam_numbered_diagram.jpg"
SAM_OUTPUT_JSON = "2_SAM/region_coordinates.json"
SAM_CHECKPOINT = "mobile_sam.pt"
SAM_CHECKPOINT_URL = (
    "https://github.com/ultralytics/assets/releases/download/v8.2.0/mobile_sam.pt"
)

# 6. Matching Configuration (3_bounding_box_id)
DECISION_JSON = "3_bounding_box_id/detected_regions.json"

# 7. Final Draw Configuration (4_draw_bbox)
FINAL_OUTPUT_IMAGE = "4_draw_bbox/final_annotated_output.jpg"
