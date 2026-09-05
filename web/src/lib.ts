export type Account = {
  name: string
  type: "checking" | "shared" | "job" | "gang"
  label: string
  owner: string
  balance: number
  canManage: boolean
  users?: string[]
}

export type Transaction = {
  id: number
  citizenid?: string
  amount: number
  reason: string
  statement_type: "deposit" | "withdraw"
  date: string | number
}

export type Snapshot = {
  mode: "bank" | "atm"
  locked: boolean
  profile: { name: string; accountNumber: string; cash: number }
  accounts: Account[]
  transactions: Record<string, Transaction[]>
  limits: { daily?: number; maxAccounts: number }
}

declare global {
  interface Window { GetParentResourceName?: () => string; invokeNative?: (...args: unknown[]) => unknown }
}

const browser = typeof window.invokeNative !== "function"

export async function fetchNui<T>(name: string, data: unknown = {}): Promise<T> {
  if (browser) return {} as T
  const resource = window.GetParentResourceName?.() ?? "qbbanking"
  const response = await fetch(`https://${resource}/${name}`, {
    method: "POST", headers: { "Content-Type": "application/json" }, body: JSON.stringify(data),
  })
  if (!response.ok) throw new Error(`NUI request failed (${response.status})`)
  return response.json() as Promise<T>
}

export function money(value: number) {
  return new Intl.NumberFormat("en-US", { style: "currency", currency: "USD", maximumFractionDigits: 0 }).format(value)
}

export function relativeDate(value: string | number) {
  const date = new Date(value)
  return Number.isNaN(date.getTime()) ? "Recently" : date.toLocaleString([], { month: "short", day: "numeric", hour: "numeric", minute: "2-digit" })
}
