from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware

from app.routers import accounts

app = FastAPI(title="Profolio API")

app.add_middleware(
    CORSMiddleware,
    allow_origin_regex=r"http://(localhost|127\.0\.0\.1):\d+",
    allow_methods=["GET"],
    allow_headers=["*"],
)

app.include_router(accounts.router, prefix="/api")


@app.get("/health")
def health():
    return {"status": "ok"}
