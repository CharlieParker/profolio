import os

# Set before app.database is imported: Settings() is built at import time,
# and a real env var takes precedence over any local .env file.
# Port 1 has no listener, so an accidental DB call fails fast.
os.environ["DATABASE_URL"] = "postgresql+psycopg://test:test@127.0.0.1:1/test"
