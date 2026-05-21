import logging
from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware

from app.api.routes import router as ai_router
from app.core.settings import settings

logger = logging.getLogger(__name__)

app = FastAPI(
    title="Mental Health AI Engine",
    description="AI service for emotional support, mood analysis, moderation, and wellness planning",
    version="2.0.0",
    docs_url="/docs",
    openapi_url="/openapi.json"
)

app.add_middleware(
    CORSMiddleware,
    allow_origins=settings.parsed_cors_origins,
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)


@app.get("/")
def root() -> dict:
    """Root endpoint with service info."""
    return {
        "name": "Mental Health AI Engine",
        "environment": settings.env,
        "version": "2.0.0",
        "docs": "/docs",
        "status": "operational"
    }


@app.on_event("startup")
async def startup_event():
    """Log startup information."""
    logger.info(f"Starting Mental Health AI Engine in {settings.env} mode")
    logger.info(f"Debug mode: {settings.debug}")
    logger.info(f"CORS origins: {settings.parsed_cors_origins}")


@app.on_event("shutdown")
async def shutdown_event():
    """Log shutdown information."""
    logger.info("Shutting down Mental Health AI Engine")


app.include_router(ai_router)


if __name__ == "__main__":
    import uvicorn

    logger.info(f"Launching uvicorn server on {settings.api_host}:{settings.api_port}")
    uvicorn.run(
        "main:app",
        host=settings.api_host,
        port=settings.api_port,
        reload=settings.debug,
        log_level=settings.log_level.lower(),
    )

