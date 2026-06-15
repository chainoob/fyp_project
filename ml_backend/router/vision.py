import logging
import asyncio
from fastapi import APIRouter, UploadFile, File, HTTPException, Depends
from google.cloud import vision
from utils.auth import verify_firebase_token

logger = logging.getLogger(__name__)
router = APIRouter()
vision_client = vision.ImageAnnotatorClient()

VALID_APPLIANCES = {"kettle", "iron", "lamp", "laptop", "charger", "fan", "printer"}
CONFIDENCE_THRESHOLD = 0.60 

@router.post("/api/v1/recognize-appliance")
async def recognize_appliance(file: UploadFile = File(...), token: dict = Depends(verify_firebase_token)):
    try:
        content = await file.read()
        
        if len(content) > 5 * 1024 * 1024:
            raise HTTPException(status_code=413, detail="Image too large. Max 5MB allowed.")

        image = vision.Image(content=content)
        
        # Developer Expectation: Offload synchronous I/O block to worker thread pool
        response = await asyncio.to_thread(vision_client.label_detection, image=image)
        
        if response.error.message:
            logger.error(f"Vision API Error: {response.error.message}")
            raise HTTPException(status_code=500, detail="Vision AI Service Error.")

        labels = response.label_annotations
        top_guesses = [label.description.capitalize() for label in labels[:5]]
        
        detected = "Unknown"
        confidence = 0.0

        # Developer Expectation: Exact tokens eliminate substring vocabulary bleeding
        MAPPING_RULES = {
            "kettle": {"kettle", "small appliance", "pitcher", "electric kettle"},
            "iron": {"iron", "clothes iron", "clothes steamer", "smoothing iron"},
            "lamp": {"lamp", "lighting", "light bulb", "lantern", "table lamp"},
            "laptop": {"laptop", "computer", "notebook", "netbook", "personal computer"},
            "charger": {"charger", "adapter", "cable", "wire", "electronic engineering", "power supply"},
            "fan": {"fan", "mechanical fan", "cooling", "electric fan"},
            "printer": {"printer", "inkjet", "laserjet", "copier", "multi-function printer"}
        }

        matches = {}
        for label in labels:
            desc_lower = label.description.lower().strip()
            score = label.score
            
            if score < CONFIDENCE_THRESHOLD:
                continue

            for app, synonyms in MAPPING_RULES.items():
                if desc_lower in synonyms:
                    if app not in matches or score > matches[app]:
                        matches[app] = score

        has_explicit_laptop = any(
            any(term in l.description.lower() for term in ["laptop", "notebook", "netbook"])
            for l in labels if l.score >= CONFIDENCE_THRESHOLD
        )
        
        has_explicit_printer = any(
            any(term in l.description.lower() for term in ["printer", "inkjet", "laserjet", "copier"])
            for l in labels if l.score >= CONFIDENCE_THRESHOLD
        )

        # Developer Expectation: Symmetric negative reinforcement resolves overlapping computer tokens
        if "laptop" in matches and "printer" in matches:
            if has_explicit_printer and not has_explicit_laptop:
                detected = "Printer"
                confidence = matches["printer"]
            elif has_explicit_laptop and not has_explicit_printer:
                detected = "Laptop"
                confidence = matches["laptop"]
            else:
                detected = "Laptop" if matches["laptop"] >= matches["printer"] else "Printer"
                confidence = matches[detected.lower()]
        elif has_explicit_printer and "laptop" in matches and not has_explicit_laptop:
            detected = "Printer"
            confidence = matches.get("printer", matches["laptop"])
        elif matches:
            best_app = max(matches, key=matches.get)
            detected = best_app.capitalize()
            confidence = matches[best_app]

        logger.info(f"Vision Recognition Result: {detected} (Confidence: {confidence:.2f})")

        return {
            "success": detected != "Unknown",
            "appliance": detected,
            "confidence": confidence,
            "top_guesses": top_guesses
        }
    except HTTPException:
        raise
    except Exception as e:
        logger.error(f"Vision Pipeline Critical Failure: {str(e)}", exc_info=True)
        raise HTTPException(status_code=500, detail="Failed to process image recognition.")