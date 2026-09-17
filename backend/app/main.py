from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware

from app.routers import accounts

app = FastAPI(title="Profolio API")

app.add_middleware(
    CORSMiddleware,
    allow_origins=[
        "http://localhost:5173",
        "http://127.0.0.1:5173",
        "http://localhost:8080",
        "http://127.0.0.1:8080",
    ],
    allow_methods=["GET"],
    allow_headers=["*"],
)

app.include_router(accounts.router)


@app.get("/health")
def health():
    return {"status": "ok"}
