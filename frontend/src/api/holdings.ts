export interface Holding {
  id: number;
  instrument: string;
  isin: string;
  quantity: number;
  price: number;
  market_value: number;
}

export async function getAccountHoldings(
  accountId: number,
): Promise<Holding[]> {
  const res = await fetch(`/api/accounts/${accountId}/holdings`);
  if (!res.ok) {
    throw new Error(`Failed to load holdings: ${res.status}`);
  }
  return res.json();
}
