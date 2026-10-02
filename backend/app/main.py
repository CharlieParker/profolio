from fastapi import FastAPI

from app.routers import accounts, version

app = FastAPI(title="Profolio API")

app.include_router(accounts.router, prefix="/api")
# under /api so it is reachable through the frontend's proxy; /health stays at the
# root, where only the kubelet's probes (and a port-forward) reach it
app.include_router(version.router, prefix="/api")


@app.get("/health")
def health():
    return {"status": "ok"}
