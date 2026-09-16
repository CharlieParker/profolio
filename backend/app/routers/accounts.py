from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy import func, select
from sqlalchemy.orm import Session

from app.database import get_db
from app.models import Account, Holding
from app.schemas import AccountSummary, HoldingOut

router = APIRouter()


@router.get("/accounts/{account_id}/holdings", response_model=list[HoldingOut])
def get_account_holdings(account_id: int, db: Session = Depends(get_db)):
    account = db.get(Account, account_id)
    if account is None:
        raise HTTPException(status_code=404, detail="Account not found")
    return account.holdings


@router.get("/accounts/summary", response_model=list[AccountSummary])
def get_accounts_summary(db: Session = Depends(get_db)):
    rows = db.execute(
        select(
            Account.id,
            Account.name,
            func.count(Holding.id).label("holding_count"),
            func.coalesce(func.sum(Holding.quantity * Holding.price), 0).label(
                "total_value"
            ),
        )
        .join(Holding, Holding.account_id == Account.id, isouter=True)
        .group_by(Account.id, Account.name)
        .order_by(Account.id)
    ).all()

    return [
        AccountSummary(
            account_id=row.id,
            account_name=row.name,
            holding_count=row.holding_count,
            total_value=float(row.total_value),
        )
        for row in rows
    ]
