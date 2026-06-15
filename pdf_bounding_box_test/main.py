import os
import sys
import shutil
import json
import logging
import asyncio
from pathlib import Path
from fastapi import FastAPI, File, UploadFile, HTTPException, Form
from fastapi.responses import FileResponse, JSONResponse
from fastapi.middleware.cors import CORSMiddleware

# Set up logger
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger("pdf_bbox_service")

# Resolve directories
CURRENT_DIR = Path(__file__).resolve().parent
sys.path.append(str(CURRENT_DIR))
sys.path.append(str(CURRENT_DIR / "1_bounding_box_choice"))
sys.path.append(str(CURRENT_DIR / "2_OpenCV"))
sys.path.append(str(CURRENT_DIR / "2_OpenCV_morph"))
sys.path.append(str(CURRENT_DIR / "2_SAM"))
sys.path.append(str(CURRENT_DIR / "3_bounding_box_id"))
sys.path.append(str(CURRENT_DIR / "4_draw_bbox"))

# Load config
try:
    import config

    logger.info("Loaded config module successfully")
except Exception as e:
    config = None
    logger.error(f"Failed to import config module: {e}", exc_info=True)

# Import logic modules (handles compiled .pyc imports)
try:
    import opencv

    logger.info("Loaded opencv module successfully")
except Exception as e:
    opencv = None
    logger.warning(f"opencv module not loaded: {e}", exc_info=True)

try:
    import opencv_morph

    logger.info("Loaded opencv_morph module successfully")
except Exception as e:
    opencv_morph = None
    logger.warning(f"opencv_morph module not loaded: {e}", exc_info=True)

try:
    import Mobile_SAM

    logger.info("Loaded Mobile_SAM module successfully")
except Exception as e:
    Mobile_SAM = None
    logger.warning(f"Mobile_SAM module not loaded: {e}", exc_info=True)

try:
    import gpt_bbox

    logger.info("Loaded gpt_bbox module successfully")
except Exception as e:
    gpt_bbox = None
    logger.warning(f"gpt_bbox module not loaded: {e}", exc_info=True)

try:
    import query_gpt

    logger.info("Loaded query_gpt module successfully")
except Exception as e:
    query_gpt = None
    logger.warning(f"query_gpt module not loaded: {e}", exc_info=True)

try:
    import draw_bbox_1

    logger.info("Loaded draw_bbox_1 module successfully")
except Exception as e:
    draw_bbox_1 = None
    logger.warning(f"draw_bbox_1 module not loaded: {e}", exc_info=True)


app = FastAPI(
    title="PDF Bounding Box Service API",
    description="A containerized REST API that wraps the PDF bounding box extraction algorithms.",
    version="1.0.0",
)

pipeline_lock = asyncio.Lock()


app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)


@app.get("/health")
def health():
    return {
        "status": "ok",
        "modules_loaded": {
            "config": config is not None,
            "opencv": opencv is not None,
            "opencv_morph": opencv_morph is not None,
            "sam": Mobile_SAM is not None,
            "gpt_bbox": gpt_bbox is not None,
            "gpt": query_gpt is not None,
            "draw_bbox": draw_bbox_1 is not None,
        },
    }


def save_uploaded_file(upload_file: UploadFile, target_path: str):
    """Saves a temporary uploaded file to the specified disk path."""
    dest = Path(target_path)
    dest.parent.mkdir(parents=True, exist_ok=True)
    with dest.open("wb") as buffer:
        shutil.copyfileobj(upload_file.file, buffer)


@app.post("/detect/opencv")
async def detect_opencv(file: UploadFile = File(...)):
    if not opencv or not config:
        raise HTTPException(
            status_code=503, detail="OpenCV detection module is not available"
        )

    # Use a temp input image path
    temp_input_path = CURRENT_DIR / "temp_input_opencv.jpg"
    save_uploaded_file(file, str(temp_input_path))

    try:
        # Calls the compiled OpenCV code
        opencv.extract_diagram_regions(str(temp_input_path))

        # Read the resulting coordinates json as configured in config
        out_json_path = CURRENT_DIR / config.OPENCV_OUTPUT_JSON
        if not out_json_path.exists():
            raise HTTPException(
                status_code=500,
                detail="Resulting JSON coordinates file was not created by OpenCV module",
            )

        with open(out_json_path, "r", encoding="utf-8") as f:
            data = json.load(f)
        return data
    except Exception as e:
        logger.error(f"OpenCV detection failed: {e}")
        raise HTTPException(status_code=500, detail=str(e))
    finally:
        if temp_input_path.exists():
            temp_input_path.unlink()


@app.post("/detect/opencv-morph")
async def detect_opencv_morph(file: UploadFile = File(...)):
    if not opencv_morph or not config:
        raise HTTPException(
            status_code=503, detail="OpenCV morphology module is not available"
        )

    temp_input_path = CURRENT_DIR / "temp_input_morph.jpg"
    save_uploaded_file(file, str(temp_input_path))

    try:
        opencv_morph.extract_regions_with_morphology(str(temp_input_path))

        out_json_path = CURRENT_DIR / config.MORPH_OUTPUT_JSON
        if not out_json_path.exists():
            raise HTTPException(
                status_code=500,
                detail="Resulting JSON coordinates file was not created by morphology module",
            )

        with open(out_json_path, "r", encoding="utf-8") as f:
            data = json.load(f)
        return data
    except Exception as e:
        logger.error(f"OpenCV morphology detection failed: {e}")
        raise HTTPException(status_code=500, detail=str(e))
    finally:
        if temp_input_path.exists():
            temp_input_path.unlink()


@app.post("/detect/sam")
async def detect_sam(file: UploadFile = File(...)):
    if not Mobile_SAM or not config:
        raise HTTPException(status_code=503, detail="MobileSAM module is not available")

    # Ensure MobileSAM checkpoint exists; download it if it doesn't
    checkpoint_path = CURRENT_DIR / config.SAM_CHECKPOINT
    if not checkpoint_path.exists():
        logger.info("MobileSAM checkpoint model not found. Downloading...")
        try:
            Mobile_SAM.download_checkpoint(
                str(checkpoint_path), config.SAM_CHECKPOINT_URL
            )
        except Exception as e:
            logger.error(f"Failed to download checkpoint: {e}")
            raise HTTPException(
                status_code=500,
                detail=f"Failed to download MobileSAM model checkpoint: {e}",
            )

    temp_input_path = CURRENT_DIR / "temp_input_sam.jpg"
    save_uploaded_file(file, str(temp_input_path))

    try:
        Mobile_SAM.generate_numbered_diagram(str(temp_input_path))

        out_json_path = CURRENT_DIR / config.SAM_OUTPUT_JSON
        if not out_json_path.exists():
            raise HTTPException(
                status_code=500,
                detail="Resulting coordinates JSON not generated by MobileSAM",
            )

        with open(out_json_path, "r", encoding="utf-8") as f:
            data = json.load(f)
        return data
    except Exception as e:
        logger.error(f"MobileSAM detection failed: {e}")
        raise HTTPException(status_code=500, detail=str(e))
    finally:
        if temp_input_path.exists():
            temp_input_path.unlink()


@app.post("/detect/gemini")
async def detect_gemini(file: UploadFile = File(...)):
    if not gpt_bbox or not config:
        raise HTTPException(
            status_code=503, detail="GPT matching module is not available"
        )

    # gpt_bbox.main reads config.INPUT_IMAGE, so we save the uploaded file there
    input_image_path = CURRENT_DIR / config.INPUT_IMAGE
    save_uploaded_file(file, str(input_image_path))

    try:
        # Run module main
        gpt_bbox.main()

        out_json_path = CURRENT_DIR / config.DECISION_JSON
        if not out_json_path.exists():
            raise HTTPException(
                status_code=500, detail="GPT matching output coordinates not generated"
            )

        with open(out_json_path, "r", encoding="utf-8") as f:
            data = json.load(f)
        return data
    except Exception as e:
        logger.error(f"Gemini query failed: {e}")
        raise HTTPException(status_code=500, detail=str(e))
    finally:
        if input_image_path.exists():
            input_image_path.unlink()


@app.post("/detect/gpt")
async def detect_gpt(file: UploadFile = File(...)):
    if not query_gpt or not config:
        raise HTTPException(status_code=503, detail="GPT query module is not available")

    # query_gpt.main reads config.INPUT_IMAGE, so we save the uploaded file there
    input_image_path = CURRENT_DIR / config.INPUT_IMAGE
    save_uploaded_file(file, str(input_image_path))

    try:
        # Run module main
        query_gpt.main()

        out_json_path = CURRENT_DIR / config.GPT_OUTPUT_JSON
        if not out_json_path.exists():
            raise HTTPException(
                status_code=500, detail="GPT output coordinates not generated"
            )

        with open(out_json_path, "r", encoding="utf-8") as f:
            data = json.load(f)
        return data
    except Exception as e:
        logger.error(f"GPT query failed: {e}")
        raise HTTPException(status_code=500, detail=str(e))
    finally:
        if input_image_path.exists():
            input_image_path.unlink()


@app.post("/draw")
async def draw_bounding_boxes(
    file: UploadFile = File(...), coordinates_file: UploadFile = File(...)
):
    if not draw_bbox_1 or not config:
        raise HTTPException(
            status_code=503, detail="Draw bounding box module is not available"
        )

    input_image_path = CURRENT_DIR / config.INPUT_IMAGE
    save_uploaded_file(file, str(input_image_path))

    # draw_bbox_1 reads coordinates from config.DECISION_JSON
    coordinates_path = CURRENT_DIR / config.DECISION_JSON
    save_uploaded_file(coordinates_file, str(coordinates_path))

    try:
        draw_bbox_1.main()

        out_image_path = CURRENT_DIR / config.FINAL_OUTPUT_IMAGE
        if not out_image_path.exists():
            raise HTTPException(
                status_code=500, detail="Final annotated image not generated"
            )

        return FileResponse(out_image_path, media_type="image/jpeg")
    except Exception as e:
        logger.error(f"Draw bounding box failed: {e}")
        raise HTTPException(status_code=500, detail=str(e))
    finally:
        if input_image_path.exists():
            input_image_path.unlink()
        if coordinates_path.exists():
            coordinates_path.unlink()


@app.post("/detect/pipeline")
async def detect_pipeline(file: UploadFile = File(...)):
    if not all([query_gpt, opencv, opencv_morph, gpt_bbox, config]):
        raise HTTPException(
            status_code=503,
            detail="Required modules (gpt, opencv, morphology, or gpt_bbox) are not loaded",
        )

    async with pipeline_lock:
        input_image_path = CURRENT_DIR / config.INPUT_IMAGE
        out_gpt_json = CURRENT_DIR / config.GPT_OUTPUT_JSON
        out_opencv_json = CURRENT_DIR / config.OPENCV_OUTPUT_JSON
        out_morph_json = CURRENT_DIR / config.MORPH_OUTPUT_JSON
        out_gemini_json = CURRENT_DIR / config.DECISION_JSON

        opencv_output_image = CURRENT_DIR / config.OPENCV_OUTPUT_IMAGE
        morph_output_image = CURRENT_DIR / config.MORPH_OUTPUT_IMAGE

        # 1. Save uploaded file to configured input path
        save_uploaded_file(file, str(input_image_path))

        try:
            # 2. Run Step 1: GPT Bounding Box Choice Recommendation
            query_gpt.main()
            if not out_gpt_json.exists():
                raise HTTPException(
                    status_code=500, detail="GPT recommendations file was not generated"
                )

            # 3. Run Step 2a: OpenCV Contour Segmentation
            opencv.extract_diagram_regions(str(input_image_path))
            if not out_opencv_json.exists():
                raise HTTPException(
                    status_code=500,
                    detail="OpenCV region coordinates were not generated",
                )

            # 4. Run Step 2b: OpenCV Morphology Segmentation
            opencv_morph.extract_regions_with_morphology(str(input_image_path))
            if not out_morph_json.exists():
                raise HTTPException(
                    status_code=500,
                    detail="OpenCV morphology coordinates were not generated",
                )

            # 5. Run Step 3: GPT Matching
            gpt_bbox.main(sources=["OPENCV", "OPENCV_MORPH"])
            if not out_gemini_json.exists():
                raise HTTPException(
                    status_code=500,
                    detail="GPT matching coordinate mapping results were not generated",
                )

            # 6. Load and parse the coordinate files
            with open(out_gemini_json, "r", encoding="utf-8") as f:
                decisions = json.load(f)
            with open(out_opencv_json, "r", encoding="utf-8") as f:
                opencv_coords = json.load(f)
            with open(out_morph_json, "r", encoding="utf-8") as f:
                morph_coords = json.load(f)

            coordinates_data = {"OPENCV": opencv_coords, "OPENCV_MORPH": morph_coords}

            results = []

            # 7. Parse decisions and lookup/merge coordinates
            for item in decisions:
                source = item.get("source", "OPENCV_MORPH")
                item_ids = item.get("ids")
                if item_ids is None and "id" in item:
                    val = item.get("id")
                    item_ids = [str(val)] if val is not None else []
                elif isinstance(item_ids, list):
                    item_ids = [str(mid) for mid in item_ids if mid is not None]
                else:
                    item_ids = []

                label = item.get("label") or item.get("text") or "Target"
                color_name = item.get("color", "red")

                # Use morph coordinates as fallback if source is OPENCV but not generated
                if source not in coordinates_data:
                    source_coords = morph_coords
                else:
                    source_coords = coordinates_data[source]

                y_min_merged, x_min_merged = float("inf"), float("inf")
                y_max_merged, x_max_merged = float("-inf"), float("-inf")
                valid_ids = []

                for item_id in item_ids:
                    if item_id in source_coords:
                        y_min, x_min, y_max, x_max = source_coords[item_id]
                        y_min_merged = min(y_min_merged, y_min)
                        x_min_merged = min(x_min_merged, x_min)
                        y_max_merged = max(y_max_merged, y_max)
                        x_max_merged = max(x_max_merged, x_max)
                        valid_ids.append(item_id)

                if not valid_ids:
                    continue

                # Format coordinates as [x_min, y_min, x_max, y_max] to match Dart expectations
                results.append(
                    {
                        "label": label,
                        "color": color_name,
                        "box": [
                            float(x_min_merged),
                            float(y_min_merged),
                            float(x_max_merged),
                            float(y_max_merged),
                        ],
                    }
                )

            return results

        except Exception as e:
            logger.error(f"Pipeline processing failed: {e}")
            raise HTTPException(status_code=500, detail=str(e))

        finally:
            # Clean up all created files and images to keep storage clean
            paths_to_clean = [
                input_image_path,
                out_gpt_json,
                out_opencv_json,
                out_morph_json,
                out_gemini_json,
                opencv_output_image,
                morph_output_image,
            ]
            for path in paths_to_clean:
                if path.exists():
                    try:
                        path.unlink()
                    except Exception:
                        pass


@app.post("/detect/agent-pipeline")
async def detect_agent_pipeline(
    file: UploadFile = File(...),
    targets: str = Form(
        ...
    ),  # JSON string representing the targets array from the agent
):
    if not all([opencv, opencv_morph, gpt_bbox, config]):
        raise HTTPException(
            status_code=503,
            detail="Required modules (opencv, morphology, or gpt_bbox) are not loaded",
        )

    async with pipeline_lock:
        input_image_path = CURRENT_DIR / config.INPUT_IMAGE
        out_gpt_json = CURRENT_DIR / config.GPT_OUTPUT_JSON
        out_opencv_json = CURRENT_DIR / config.OPENCV_OUTPUT_JSON
        out_morph_json = CURRENT_DIR / config.MORPH_OUTPUT_JSON
        out_gemini_json = CURRENT_DIR / config.DECISION_JSON

        opencv_output_image = CURRENT_DIR / config.OPENCV_OUTPUT_IMAGE
        morph_output_image = CURRENT_DIR / config.MORPH_OUTPUT_IMAGE

        # 1. Save uploaded file to configured input path
        save_uploaded_file(file, str(input_image_path))

        try:
            # 2. Parse and save targets directly, replacing Step 1 (query_gpt)
            try:
                targets_data = json.loads(targets)
                if not isinstance(targets_data, list):
                    raise ValueError("targets must be a JSON array")
            except Exception as e:
                raise HTTPException(
                    status_code=400, detail=f"Invalid targets JSON format: {e}"
                )

            out_gpt_json.parent.mkdir(parents=True, exist_ok=True)
            with open(out_gpt_json, "w", encoding="utf-8") as f:
                json.dump(targets_data, f, indent=4)

            # 3. Run Step 2a: OpenCV Contour Segmentation
            opencv.extract_diagram_regions(str(input_image_path))
            if not out_opencv_json.exists():
                raise HTTPException(
                    status_code=500,
                    detail="OpenCV region coordinates were not generated",
                )

            # 4. Run Step 2b: OpenCV Morphology Segmentation
            opencv_morph.extract_regions_with_morphology(str(input_image_path))
            if not out_morph_json.exists():
                raise HTTPException(
                    status_code=500,
                    detail="OpenCV morphology coordinates were not generated",
                )

            # 5. Run Step 3: GPT Matching
            gpt_bbox.main(sources=["OPENCV", "OPENCV_MORPH"])
            if not out_gemini_json.exists():
                raise HTTPException(
                    status_code=500,
                    detail="GPT matching coordinate mapping results were not generated",
                )

            # 6. Load and parse the coordinate files
            with open(out_gemini_json, "r", encoding="utf-8") as f:
                decisions = json.load(f)
            with open(out_opencv_json, "r", encoding="utf-8") as f:
                opencv_coords = json.load(f)
            with open(out_morph_json, "r", encoding="utf-8") as f:
                morph_coords = json.load(f)

            coordinates_data = {"OPENCV": opencv_coords, "OPENCV_MORPH": morph_coords}

            results = []

            # 7. Parse decisions and lookup/merge coordinates
            for item in decisions:
                source = item.get("source", "OPENCV_MORPH")
                item_ids = item.get("ids")
                if item_ids is None and "id" in item:
                    val = item.get("id")
                    item_ids = [str(val)] if val is not None else []
                elif isinstance(item_ids, list):
                    item_ids = [str(mid) for mid in item_ids if mid is not None]
                else:
                    item_ids = []

                label = item.get("label") or item.get("text") or "Target"
                color_name = item.get("color", "red")

                # Use morph coordinates as fallback if source is OPENCV but not generated
                if source not in coordinates_data:
                    source_coords = morph_coords
                else:
                    source_coords = coordinates_data[source]

                y_min_merged, x_min_merged = float("inf"), float("inf")
                y_max_merged, x_max_merged = float("-inf"), float("-inf")
                valid_ids = []

                for item_id in item_ids:
                    if item_id in source_coords:
                        y_min, x_min, y_max, x_max = source_coords[item_id]
                        y_min_merged = min(y_min_merged, y_min)
                        x_min_merged = min(x_min_merged, x_min)
                        y_max_merged = max(y_max_merged, y_max)
                        x_max_merged = max(x_max_merged, x_max)
                        valid_ids.append(item_id)

                if not valid_ids:
                    continue

                # Format coordinates as [x_min, y_min, x_max, y_max] to match Dart expectations
                results.append(
                    {
                        "label": label,
                        "color": color_name,
                        "box": [
                            float(x_min_merged),
                            float(y_min_merged),
                            float(x_max_merged),
                            float(y_max_merged),
                        ],
                    }
                )

            return results

        except Exception as e:
            logger.error(f"Agent pipeline processing failed: {e}")
            raise HTTPException(status_code=500, detail=str(e))

        finally:
            # Clean up all created files and images to keep storage clean
            paths_to_clean = [
                input_image_path,
                out_gpt_json,
                out_opencv_json,
                out_morph_json,
                out_gemini_json,
                opencv_output_image,
                morph_output_image,
            ]
            for path in paths_to_clean:
                if path.exists():
                    try:
                        path.unlink()
                    except Exception:
                        pass
