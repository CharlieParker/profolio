from fastapi import FastAPI

from app.routers import accounts

app = FastAPI(title="Profolio API")

app.include_router(accounts.router, prefix="/api")


@app.get("/health")
def health():
    return {"status": "ok"}
