import logging
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
        
        # Validation: Max 5MB image
        if len(content) > 5 * 1024 * 1024:
            raise HTTPException(status_code=413, detail="Image too large. Max 5MB allowed.")

        image = vision.Image(content=content)
        
        # Execute Google Cloud Vision label detection
        # We wrap this in a thread if it's blocking, but usually vision client is optimized
        response = vision_client.label_detection(image=image)
        
        if response.error.message:
            logger.error(f"Vision API Error: {response.error.message}")
            raise HTTPException(status_code=500, detail="Vision AI Service Error.")

        labels = response.label_annotations
        top_guesses = [label.description.capitalize() for label in labels[:5]]
        
        detected = "Unknown"
        confidence = 0.0

        # NLP Mapping: Bridge Vision's generic vocabulary to our specific hostel assets
        MAPPING_RULES = {
            "kettle": ["kettle", "small appliance", "pitcher", "electric kettle"],
            "iron": ["iron", "clothes iron", "clothes steamer", "smoothing iron"],
            "lamp": ["lamp", "lighting", "light bulb", "lantern", "table lamp"],
            "laptop": ["laptop", "computer", "notebook", "netbook", "personal computer"],
            "charger": ["charger", "adapter", "cable", "wire", "electronic engineering", "power supply"],
            "fan": ["fan", "mechanical fan", "cooling", "electric fan"],
            "printer": ["printer", "peripheral", "office equipment", "computer hardware"]
        }

        # Filter detected labels against rules
        for label in labels:
            desc = label.description.lower()
            for app, synonyms in MAPPING_RULES.items():
                if any(syn in desc for syn in synonyms) and label.score >= CONFIDENCE_THRESHOLD:
                    detected = app.capitalize()
                    confidence = label.score
                    break
            if detected != "Unknown":
                break

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