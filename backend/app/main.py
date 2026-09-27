from fastapi import FastAPI

app = FastAPI(
    title="NETRA API",
    version="0.1.0",
)


@app.get("/")
def root():
    return {
        "name": "NETRA",
        "version": "0.1.0",
        "status": "running",
    }


@app.get("/health")
def health():
    return {
        "status": "healthy",
    }
