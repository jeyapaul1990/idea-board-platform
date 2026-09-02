from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy import select
from sqlalchemy.orm import Session

from app.db import get_db
from app.models import Idea
from app.schemas import IdeaCreate, IdeaRead

router = APIRouter(prefix="/api")


@router.get("/ideas", response_model=list[IdeaRead])
def list_ideas(db: Session = Depends(get_db)) -> list[Idea]:
    return list(db.scalars(select(Idea).order_by(Idea.created_at.desc())).all())


@router.post("/ideas", response_model=IdeaRead, status_code=status.HTTP_201_CREATED)
def create_idea(payload: IdeaCreate, db: Session = Depends(get_db)) -> Idea:
    idea = Idea(content=payload.content.strip())
    if not idea.content:
        raise HTTPException(status_code=400, detail="content cannot be empty")
    db.add(idea)
    db.commit()
    db.refresh(idea)
    return idea
