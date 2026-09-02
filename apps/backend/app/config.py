from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    model_config = SettingsConfigDict(env_file=".env", extra="ignore")

    database_url: str = "postgresql://ideas:ideas@localhost:5432/ideas"
    force_readiness_fail: bool = False


settings = Settings()
