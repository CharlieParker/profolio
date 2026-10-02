from fastapi import APIRouter

from app.database import settings
from app.schemas import VersionOut

router = APIRouter()

SERVICE = "profolio-backend"
REPO_URL = "https://github.com/CharlieParker/profolio"


@router.get("/version", response_model=VersionOut)
def get_version():
    # Which code is running: the commit this image was built from, not the tip of main.
    # A build made without the GIT_SHA build arg has no commit to link to.
    sha = settings.git_sha or "unknown"
    commit_url = None if sha == "unknown" else f"{REPO_URL}/commit/{sha}"
    return VersionOut(service=SERVICE, commit=sha, commit_url=commit_url)
