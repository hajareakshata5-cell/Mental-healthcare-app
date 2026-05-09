from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
from datetime import datetime
import os
from dotenv import load_dotenv

load_dotenv()

app = FastAPI(
    title="Mental Health AI Engine",
    description="FastAPI backend for AI-powered mental health support",
    version="1.0.0"
)

# CORS middleware
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

@app.get("/")
def read_root():
    return {
        "message": "Mental Health App AI Engine Running",
        "version": "1.0.0",
        "timestamp": datetime.now().isoformat(),
        "environment": os.getenv("ENV", "development")
    }

@app.get("/health")
def health_check():
    return {"status": "healthy"}

@app.get("/api/mood/predict")
def predict_mood(text: str = ""):
    return {
        "input": text,
        "predicted_mood": "neutral",
        "confidence": 0.85,
        "recommendations": ["Practice mindfulness", "Stay hydrated"]
    }

if __name__ == "__main__":
    import uvicorn
    uvicorn.run(app, host="0.0.0.0", port=8000, reload=True)
