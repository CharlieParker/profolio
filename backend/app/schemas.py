from pydantic import BaseModel, ConfigDict, computed_field


class HoldingOut(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: int
    instrument: str
    isin: str
    quantity: float
    price: float

    @computed_field
    @property
    def market_value(self) -> float:
        return self.quantity * self.price


class AccountSummary(BaseModel):
    account_id: int
    account_name: str
    holding_count: int
    total_value: float
