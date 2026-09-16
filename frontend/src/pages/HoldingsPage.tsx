import { useEffect, useState } from "react";
import {
  type ColumnDef,
  flexRender,
  getCoreRowModel,
  useReactTable,
} from "@tanstack/react-table";
import {
  Table,
  TableBody,
  TableCell,
  TableHead,
  TableHeader,
  TableRow,
} from "@/components/ui/table";
import { getAccountHoldings, type Holding } from "@/api/holdings";

// Pass 1 renders one seeded account's holdings — no account switcher yet.
const SEEDED_ACCOUNT_ID = 1;

const currency = new Intl.NumberFormat("en-GB", {
  style: "currency",
  currency: "GBP",
});

const columns: ColumnDef<Holding>[] = [
  { accessorKey: "instrument", header: "Instrument" },
  { accessorKey: "isin", header: "ISIN" },
  { accessorKey: "quantity", header: "Quantity" },
  {
    accessorKey: "price",
    header: "Price",
    cell: (info) => currency.format(info.getValue<number>()),
  },
  {
    accessorKey: "market_value",
    header: "Market value",
    cell: (info) => currency.format(info.getValue<number>()),
  },
];

export function HoldingsPage() {
  const [holdings, setHoldings] = useState<Holding[]>([]);
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    getAccountHoldings(SEEDED_ACCOUNT_ID)
      .then(setHoldings)
      .catch((err: Error) => setError(err.message));
  }, []);

  const table = useReactTable({
    data: holdings,
    columns,
    getCoreRowModel: getCoreRowModel(),
  });

  return (
    <main className="mx-auto max-w-3xl p-8">
      <h1 className="mb-4 text-2xl font-semibold">Holdings</h1>
      {error && <p className="text-red-600">{error}</p>}
      <Table>
        <TableHeader>
          {table.getHeaderGroups().map((headerGroup) => (
            <TableRow key={headerGroup.id}>
              {headerGroup.headers.map((header) => (
                <TableHead key={header.id}>
                  {flexRender(
                    header.column.columnDef.header,
                    header.getContext(),
                  )}
                </TableHead>
              ))}
            </TableRow>
          ))}
        </TableHeader>
        <TableBody>
          {table.getRowModel().rows.map((row) => (
            <TableRow key={row.id}>
              {row.getVisibleCells().map((cell) => (
                <TableCell key={cell.id}>
                  {flexRender(cell.column.columnDef.cell, cell.getContext())}
                </TableCell>
              ))}
            </TableRow>
          ))}
        </TableBody>
      </Table>
    </main>
  );
}
