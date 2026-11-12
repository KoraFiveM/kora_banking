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

export type DateOptions = {
  format?: string
  showTime?: boolean
  /** "player" formats in the browser's own time zone, "server" in UTC. */
  timeZone?: "player" | "server"
}

export type Snapshot = {
  mode: "bank" | "atm"
  locked: boolean
  profile: { name: string; accountNumber: string; cash: number }
  accounts: Account[]
  transactions: Record<string, Transaction[]>
  dates?: DateOptions
  limits: { daily?: number; maxAccounts: number }
}

declare global {
  interface Window { GetParentResourceName?: () => string; invokeNative?: (...args: unknown[]) => unknown }
}

const browser = typeof window.invokeNative !== "function"

export async function fetchNui<T>(name: string, data: unknown = {}): Promise<T> {
  if (browser) return {} as T
  const resource = window.GetParentResourceName?.() ?? "kora_banking"
  const response = await fetch(`https://${resource}/${name}`, {
    method: "POST", headers: { "Content-Type": "application/json" }, body: JSON.stringify(data),
  })
  if (!response.ok) throw new Error(`NUI request failed (${response.status})`)
  return response.json() as Promise<T>
}

export function money(value: number) {
  return new Intl.NumberFormat("en-US", { style: "currency", currency: "USD", maximumFractionDigits: 0 }).format(value)
}

/**
 * Formats a transaction epoch (Unix milliseconds) honouring Config.dateFormat / showTime / dateTimezone.
 * Returns the fallback (the server-formatted string, or "Recently") when the epoch is missing or invalid.
 */
export function formatTransactionDate(value: string | number | null | undefined, options: DateOptions = {}, fallback = "Recently") {
  const epoch = typeof value === "string" && value.trim() !== "" ? Number(value) : value
  if (typeof epoch !== "number" || !Number.isFinite(epoch) || epoch <= 0) return fallback
  const date = new Date(epoch < 100000000000 ? epoch * 1000 : epoch)
  if (Number.isNaN(date.getTime())) return fallback
  try {
    const timeZone = options.timeZone === "server" ? "UTC" : undefined
    const showTime = options.showTime !== false
    const layout = options.format
    if (layout !== "DD/MM/YYYY" && layout !== "MM/DD/YYYY" && layout !== "YYYY-MM-DD") {
      return date.toLocaleString([], { timeZone, year: "numeric", month: "2-digit", day: "2-digit", ...(showTime ? { hour: "numeric", minute: "2-digit" } : {}) })
    }
    const parts = Object.fromEntries(new Intl.DateTimeFormat("en-GB", {
      timeZone, year: "numeric", month: "2-digit", day: "2-digit", hour: "2-digit", minute: "2-digit", hourCycle: "h23",
    }).formatToParts(date).map((part) => [part.type, part.value]))
    const text = layout.replace("YYYY", parts.year).replace("MM", parts.month).replace("DD", parts.day)
    return showTime ? `${text} ${parts.hour}:${parts.minute}` : text
  } catch {
    return fallback
  }
}
