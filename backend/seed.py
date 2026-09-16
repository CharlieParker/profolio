"""Hand-seeded synthetic data. Run once against a fresh database.

No real financial data — every instrument, ISIN, quantity and price below is
made up.
"""

from app.database import SessionLocal
from app.models import Account, Holding

SEED_ACCOUNTS: dict[str, list[tuple[str, str, float, float]]] = {
    "Invest": [
        ("Northwind Global Equity ETF", "GB00FAKE0001", 120, 105.40),
        ("Aldergate Technology Fund", "GB00FAKE0002", 45, 512.10),
        ("Fictional Renewables Trust plc", "GB00FAKE0003", 300, 2.15),
    ],
    "Stocks ISA": [
        ("Harborlight Equity Income Fund", "GB00FAKE0004", 80, 6.75),
        ("Fictional Robotics Group plc", "GB00FAKE0005", 60, 14.30),
        ("Meridian World Index Fund", "GB00FAKE0006", 25, 88.60),
    ],
}


def seed() -> None:
    db = SessionLocal()
    try:
        for account_name, holdings in SEED_ACCOUNTS.items():
            account = db.query(Account).filter_by(name=account_name).one_or_none()
            if account is None:
                account = Account(name=account_name)
                db.add(account)
                db.flush()

            for instrument, isin, quantity, price in holdings:
                exists = (
                    db.query(Holding)
                    .filter_by(account_id=account.id, isin=isin)
                    .one_or_none()
                )
                if exists is None:
                    db.add(
                        Holding(
                            account_id=account.id,
                            instrument=instrument,
                            isin=isin,
                            quantity=quantity,
                            price=price,
                        )
                    )
        db.commit()
    finally:
        db.close()


if __name__ == "__main__":
    seed()
