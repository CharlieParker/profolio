export interface Holding {
  id: number;
  instrument: string;
  isin: string;
  quantity: number;
  price: number;
  market_value: number;
}

const API_URL = import.meta.env.VITE_API_URL ?? "http://localhost:8000";

export async function getAccountHoldings(
  accountId: number,
): Promise<Holding[]> {
  const res = await fetch(`${API_URL}/accounts/${accountId}/holdings`);
  if (!res.ok) {
    throw new Error(`Failed to load holdings: ${res.status}`);
  }
  return res.json();
}
