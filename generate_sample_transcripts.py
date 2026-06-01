import os
import json
import time
from datetime import datetime, timezone
from dotenv import load_dotenv
from google import genai
from google.genai import types

load_dotenv('d:/SS-AILectureNote/.env')

client = genai.Client()

audio_path = r"d:\SS-AILectureNote\assets\sample_voice_computer_arch_5_1p1-22.mp3"
output_dir = r"d:\SS-AILectureNote\sample_transcripts"

os.makedirs(output_dir, exist_ok=True)

print("Uploading file to Gemini...")
uploaded_file = client.files.upload(file=audio_path)
print(f"Uploaded file. URI: {uploaded_file.uri}")

print("Waiting for file to be processed...")
while uploaded_file.state.name == "PROCESSING":
    time.sleep(2)
    uploaded_file = client.files.get(name=uploaded_file.name)

prompt = """
You are an expert transcriptionist. Transcribe the entire audio file provided. 
I need the transcription split into exact 10-second chunks (0-10s, 10-20s, 20-30s, etc.).
Output ONLY a JSON array, where each element is an object with this exact schema:
{
  "segment_index": <int>,
  "text": <string>,
  "is_empty": <bool>
}
The segment_index should start from 1. 
Ensure there is an object for EVERY 10-second chunk from start to finish, even if empty.
Do not output any markdown formatting, only the raw JSON array.
"""

print("Generating content...")
response = client.models.generate_content(
    model="gemini-2.5-flash",
    contents=[uploaded_file, prompt],
    config=types.GenerateContentConfig(
        response_mime_type="application/json",
        temperature=0.2
    )
)

try:
    chunks = json.loads(response.text)
    
    start_time = datetime.now(timezone.utc)
    
    for chunk in chunks:
        index = chunk.get("segment_index", 1)
        text = chunk.get("text", "")
        is_empty = chunk.get("is_empty", text == "")
        
        # Format similar to transcript_export_service.dart
        chunk_time = start_time.strftime("%Y-%m-%dT%H:%M:%S.000Z")
        
        payload = {
            "timestamp": chunk_time,
            "duration_seconds": 10,
            "segment_index": index,
            "text": text,
            "is_empty": is_empty
        }
        
        filename = f"seg_{str(index).zfill(3)}.json"
        filepath = os.path.join(output_dir, filename)
        
        with open(filepath, "w", encoding="utf-8") as f:
            json.dump(payload, f, indent=2, ensure_ascii=False)
            
    print(f"Successfully generated {len(chunks)} segment files in {output_dir}")
except Exception as e:
    print(f"Error parsing or saving: {e}")
    print("Raw response:")
    print(response.text)

print("Cleaning up file from Gemini...")
try:
    client.files.delete(name=uploaded_file.name)
except:
    pass
