import {
  ArrowDownLeft, ArrowRightLeft, ArrowUpRight, Building2, CreditCard, Landmark,
  LogOut, Plus, Send, Settings, ShieldCheck, Trash2, UserRound, Users, WalletCards, X,
} from "lucide-react"
import { FormEvent, useEffect, useMemo, useState } from "react"
import { Account, fetchNui, money, relativeDate, Snapshot } from "./lib"

type View = "activity" | "cash" | "transfer" | "manage"
type NuiResult = { ok: boolean; error?: string; result?: { message: string; snapshot: Snapshot }; snapshot?: Snapshot }

function ThemeSync() {
  useEffect(() => {
    const listener = (event: MessageEvent<{ action?: string; data?: Record<string, string> }>) => {
      if (event.data?.action !== "qbbanking:theme" || !event.data.data) return
      for (const [key, value] of Object.entries(event.data.data)) {
        if (typeof value === "string") document.documentElement.style.setProperty(`--${key}`, value)
      }
    }
    window.addEventListener("message", listener)
    return () => window.removeEventListener("message", listener)
  }, [])
  return null
}

function AccountIcon({ type }: { type: Account["type"] }) {
  const Icon = type === "checking" ? UserRound : type === "job" ? Building2 : type === "gang" ? ShieldCheck : Users
  return <Icon className="h-4 w-4" aria-hidden />
}

function Field({ label, children }: { label: string; children: React.ReactNode }) {
  return <label><span className="label">{label}</span>{children}</label>
}

function CloseButton({ close }: { close: () => void }) {
  return <button className="button-ghost h-9 w-9 px-0" onClick={close} aria-label="Close banking"><X className="h-4 w-4" /></button>
}

function PinScreen({ snapshot, close, unlock }: { snapshot: Snapshot; close: () => void; unlock: (value: Snapshot) => void }) {
  const [pin, setPin] = useState("")
  const [error, setError] = useState<string>()
  const [busy, setBusy] = useState(false)

  async function submit(value = pin) {
    if (value.length !== 4 || busy) return
    setBusy(true); setError(undefined)
    const response = await fetchNui<NuiResult>("qbbanking:pin", { pin: value })
    setBusy(false)
    if (response.ok && response.snapshot) unlock(response.snapshot)
    else { setPin(""); setError(response.error ?? "Incorrect PIN.") }
  }

  function press(value: string) {
    if (value === "back") return setPin((current) => current.slice(0, -1))
    const next = (pin + value).slice(0, 4)
    setPin(next); setError(undefined)
    if (next.length === 4) void submit(next)
  }

  return (
    <main className="app-surface relative w-[390px] p-6">
      <div className="absolute right-4 top-4"><CloseButton close={close} /></div>
      <div className="mb-6 flex h-11 w-11 items-center justify-center rounded-lg border border-brand-border bg-brand-soft text-primary"><Landmark className="h-5 w-5" /></div>
      <p className="text-xs font-semibold uppercase tracking-[.12em] text-primary">QBCore ATM</p>
      <h1 className="mt-1 text-xl font-semibold">Welcome, {snapshot.profile.name.split(" ")[0]}</h1>
      <p className="mt-1 text-sm text-muted-foreground">Enter the 4-digit PIN for your bank card.</p>
      <div className="my-6 flex justify-center gap-3" aria-label={`${pin.length} of 4 PIN digits entered`}>
        {[0, 1, 2, 3].map((index) => <span key={index} className={`h-3 w-3 rounded-full border ${index < pin.length ? "border-primary bg-primary" : "border-input bg-surface-raised"}`} />)}
      </div>
      <div className="grid grid-cols-3 gap-2">
        {[1,2,3,4,5,6,7,8,9].map((number) => <button key={number} className="button-secondary h-12 font-mono text-base" onClick={() => press(String(number))}>{number}</button>)}
        <button className="button-ghost h-12 text-xs" onClick={() => setPin("")}>Clear</button>
        <button className="button-secondary h-12 font-mono text-base" onClick={() => press("0")}>0</button>
        <button className="button-ghost h-12 text-xs" onClick={() => press("back")}>Delete</button>
      </div>
      <p className={`mt-4 min-h-5 text-center text-xs ${error ? "text-destructive" : "text-muted-foreground"}`}>{error ?? (busy ? "Checking card…" : "Your PIN never leaves the bank server.")}</p>
    </main>
  )
}

function CashForm({ account, cash, run, compact = false }: { account: Account; cash: number; run: (data: object) => Promise<boolean>; compact?: boolean }) {
  const [kind, setKind] = useState<"withdraw" | "deposit">("withdraw")
  const [amount, setAmount] = useState("")
  const [reason, setReason] = useState("")
  const [error, setError] = useState<string>()
  const [busy, setBusy] = useState(false)
  const presets = [100, 250, 500, 1000]

  async function submit(event: FormEvent) {
    event.preventDefault(); setError(undefined)
    const value = Number(amount)
    if (!Number.isFinite(value) || value <= 0) return setError("Enter an amount.")
    if (kind === "withdraw" && value > account.balance) return setError("That is more than the account balance.")
    if (kind === "deposit" && value > cash) return setError("You do not have that much cash.")
    setBusy(true)
    const ok = await run({ kind, account: account.name, amount: value, reason })
    setBusy(false)
    if (ok) { setAmount(""); setReason("") }
  }

  return <form onSubmit={submit} className={compact ? "space-y-4" : "card max-w-xl space-y-5 p-5"}>
    <div className="grid grid-cols-2 gap-2 rounded-lg bg-surface-raised p-1">
      {(["withdraw", "deposit"] as const).map((value) => <button type="button" key={value} onClick={() => { setKind(value); setError(undefined) }} className={`button ${kind === value ? "bg-card text-foreground shadow" : "text-muted-foreground"}`}>{value === "withdraw" ? <ArrowDownLeft className="h-4 w-4" /> : <ArrowUpRight className="h-4 w-4" />}{value === "withdraw" ? "Withdraw" : "Deposit"}</button>)}
    </div>
    <div className="grid grid-cols-4 gap-2">{presets.map((value) => <button type="button" key={value} className="button-secondary px-2 font-mono text-xs" onClick={() => setAmount(String(value))}>{money(value)}</button>)}</div>
    <Field label="Amount"><div className="relative"><span className="absolute left-3 top-2.5 text-muted-foreground">$</span><input className="field pl-7 font-mono" inputMode="numeric" value={amount} onChange={(event) => setAmount(event.target.value.replace(/\D/g, ""))} placeholder="0" autoFocus /></div></Field>
    {!compact && <Field label="Reference (optional)"><input className="field" value={reason} maxLength={50} onChange={(event) => setReason(event.target.value)} placeholder={kind === "withdraw" ? "Cash withdrawal" : "Cash deposit"} /></Field>}
    <div className="flex items-center justify-between gap-4"><p className={`text-xs ${error ? "text-destructive" : "text-muted-foreground"}`}>{error ?? `${money(kind === "withdraw" ? account.balance : cash)} available`}</p><button className="button-primary min-w-28" disabled={busy}>{busy ? "Working…" : kind === "withdraw" ? "Withdraw" : "Deposit"}</button></div>
  </form>
}

function ATM({ snapshot, close, run }: { snapshot: Snapshot; close: () => void; run: (data: object) => Promise<boolean> }) {
  const account = snapshot.accounts[0]
  return <main className="app-surface w-[440px]">
    <header className="flex items-center justify-between border-b border-border px-5 py-4"><div className="flex items-center gap-3"><span className="flex h-9 w-9 items-center justify-center rounded-lg bg-brand-soft text-primary"><Landmark className="h-4 w-4" /></span><div><p className="text-sm font-semibold">QBCore ATM</p><p className="text-xs text-muted-foreground">Personal banking</p></div></div><CloseButton close={close} /></header>
    <section className="border-b border-border bg-card px-6 py-5"><p className="text-xs uppercase tracking-[.08em] text-muted-foreground">Available balance</p><p className="mt-1 font-mono text-3xl font-semibold tabular-nums">{money(account.balance)}</p><p className="mt-2 text-xs text-muted-foreground">Cash on hand · {money(snapshot.profile.cash)}{snapshot.limits.daily ? ` · ${money(snapshot.limits.daily)} daily withdrawal limit` : ""}</p></section>
    <section className="p-6"><CashForm account={account} cash={snapshot.profile.cash} run={run} compact /></section>
    <footer className="flex items-center justify-between border-t border-border px-5 py-3 text-xs text-muted-foreground"><span>Session secured</span><button className="button-ghost" onClick={close}><LogOut className="h-4 w-4" />Finish</button></footer>
  </main>
}

function Activity({ account, snapshot }: { account: Account; snapshot: Snapshot }) {
  const rows = snapshot.transactions[account.name] ?? []
  return <div className="card overflow-hidden"><div className="border-b border-border px-5 py-4"><h2 className="font-semibold">Recent activity</h2><p className="mt-0.5 text-xs text-muted-foreground">Latest transactions for {account.owner}</p></div>
    {rows.length === 0 ? <div className="flex h-56 flex-col items-center justify-center text-muted-foreground"><ArrowRightLeft className="mb-3 h-6 w-6" /><p className="text-sm">No transactions yet</p></div> : <div className="scroll-thin max-h-[430px] divide-y divide-border overflow-y-auto">{rows.map((row) => {
      const incoming = row.statement_type === "deposit"
      return <div key={row.id} className="flex items-center gap-4 px-5 py-3.5"><span className={`flex h-9 w-9 items-center justify-center rounded-full ${incoming ? "bg-success/10 text-success" : "bg-surface-raised text-muted-foreground"}`}>{incoming ? <ArrowDownLeft className="h-4 w-4" /> : <ArrowUpRight className="h-4 w-4" />}</span><span className="min-w-0 flex-1"><span className="block truncate text-sm font-medium">{row.reason || (incoming ? "Deposit" : "Withdrawal")}</span><span className="block text-xs text-muted-foreground">{relativeDate(row.date)}{row.citizenid ? ` · ${row.citizenid}` : ""}</span></span><span className={`font-mono text-sm font-semibold tabular-nums ${incoming ? "text-success" : "text-foreground"}`}>{incoming ? "+" : "−"}{money(row.amount)}</span></div>
    })}</div>}
  </div>
}

function TransferForm({ accounts, selected, run }: { accounts: Account[]; selected: Account; run: (data: object) => Promise<boolean> }) {
  const [external, setExternal] = useState(false)
  const [from, setFrom] = useState(selected.name)
  const [to, setTo] = useState(accounts.find((account) => account.name !== selected.name)?.name ?? "")
  const [recipient, setRecipient] = useState("")
  const [amount, setAmount] = useState("")
  const [reason, setReason] = useState("")
  const [error, setError] = useState<string>()
  const [busy, setBusy] = useState(false)
  const source = accounts.find((account) => account.name === from) ?? selected

  async function submit(event: FormEvent) {
    event.preventDefault(); setError(undefined)
    const value = Number(amount)
    if (!Number.isFinite(value) || value <= 0) return setError("Enter an amount.")
    if (value > source.balance) return setError("That is more than the source balance.")
    if (external && !recipient.trim()) return setError("Enter the recipient account number.")
    if (!external && (!to || to === from)) return setError("Choose two different accounts.")
    setBusy(true)
    const ok = await run({ kind: "transfer", from, to: external ? undefined : to, recipient: external ? recipient : undefined, amount: value, reason })
    setBusy(false)
    if (ok) { setAmount(""); setReason("") }
  }

  return <form onSubmit={submit} className="card max-w-2xl space-y-5 p-5">
    <div className="flex gap-2">{[false, true].map((value) => <button type="button" key={String(value)} className={external === value ? "button-primary" : "button-secondary"} onClick={() => { setExternal(value); setError(undefined) }}>{value ? <Send className="h-4 w-4" /> : <ArrowRightLeft className="h-4 w-4" />}{value ? "Another player" : "My accounts"}</button>)}</div>
    <div className="grid grid-cols-2 gap-4"><Field label="From"><select className="field" value={from} onChange={(event) => setFrom(event.target.value)}>{accounts.map((account) => <option key={account.name} value={account.name}>{account.label} — {account.owner}</option>)}</select></Field>{external ? <Field label="Recipient account number"><input className="field font-mono" value={recipient} onChange={(event) => setRecipient(event.target.value)} placeholder="Citizen ID" /></Field> : <Field label="To"><select className="field" value={to} onChange={(event) => setTo(event.target.value)}>{accounts.filter((account) => account.name !== from).map((account) => <option key={account.name} value={account.name}>{account.label} — {account.owner}</option>)}</select></Field>}</div>
    <div className="grid grid-cols-2 gap-4"><Field label="Amount"><input className="field font-mono" inputMode="numeric" value={amount} onChange={(event) => setAmount(event.target.value.replace(/\D/g, ""))} placeholder="0" /></Field><Field label="Reference"><input className="field" value={reason} maxLength={50} onChange={(event) => setReason(event.target.value)} placeholder="Optional" /></Field></div>
    <div className="flex items-center justify-between"><p className={`text-xs ${error ? "text-destructive" : "text-muted-foreground"}`}>{error ?? `${money(source.balance)} available`}</p><button className="button-primary min-w-28" disabled={busy}>{busy ? "Sending…" : "Transfer"}</button></div>
  </form>
}

function Manage({ accounts, maxAccounts, run }: { accounts: Account[]; maxAccounts: number; run: (data: object) => Promise<boolean> }) {
  const owned = accounts.filter((account) => account.type === "shared" && account.canManage)
  const [account, setAccount] = useState(owned[0]?.name ?? "")
  const [name, setName] = useState("")
  const [amount, setAmount] = useState("")
  const [member, setMember] = useState("")
  const [pin, setPin] = useState("")
  const selected = owned.find((item) => item.name === account)

  async function action(data: object) { if (await run(data)) { setName(""); setAmount(""); setMember(""); setPin("") } }
  return <div className="grid grid-cols-2 gap-4">
    <section className="card p-5"><div className="mb-5 flex items-center gap-3"><span className="flex h-9 w-9 items-center justify-center rounded-lg bg-brand-soft text-primary"><Plus className="h-4 w-4" /></span><div><h2 className="font-semibold">New shared account</h2><p className="text-xs text-muted-foreground">Create up to {maxAccounts} accounts you control.</p></div></div><div className="space-y-4"><Field label="Account name"><input className="field" value={name} onChange={(event) => setName(event.target.value)} placeholder="Example: Racing fund" /></Field><Field label="Opening balance"><input className="field font-mono" inputMode="numeric" value={amount} onChange={(event) => setAmount(event.target.value.replace(/\D/g, ""))} placeholder="0" /></Field><button className="button-primary w-full" onClick={() => void action({ kind: "create", name, amount: Number(amount) })}>Create account</button></div></section>
    <section className="card p-5"><div className="mb-5 flex items-center gap-3"><span className="flex h-9 w-9 items-center justify-center rounded-lg bg-surface-raised text-muted-foreground"><CreditCard className="h-4 w-4" /></span><div><h2 className="font-semibold">Bank card</h2><p className="text-xs text-muted-foreground">Required for secure ATM access.</p></div></div><Field label="Choose a 4-digit PIN"><input className="field font-mono tracking-[.4em]" inputMode="numeric" maxLength={4} value={pin} onChange={(event) => setPin(event.target.value.replace(/\D/g, "").slice(0,4))} placeholder="••••" /></Field><button className="button-secondary mt-4 w-full" disabled={pin.length !== 4} onClick={() => void action({ kind: "orderCard", pin })}><WalletCards className="h-4 w-4" />Issue card</button></section>
    <section className="card col-span-2 p-5"><div className="mb-4 flex items-end gap-3"><div className="flex-1"><Field label="Manage shared account"><select className="field" value={account} onChange={(event) => setAccount(event.target.value)}><option value="">Select an account</option>{owned.map((item) => <option key={item.name} value={item.name}>{item.owner}</option>)}</select></Field></div></div>{selected ? <div className="grid grid-cols-2 gap-5 border-t border-border pt-5"><div className="space-y-3"><h3 className="text-sm font-semibold">Rename or close</h3><input className="field" value={name} onChange={(event) => setName(event.target.value)} placeholder="New account name" /><div className="flex gap-2"><button className="button-secondary" onClick={() => void action({ kind: "rename", account, name })}>Rename</button><button className="button-danger" onClick={() => void action({ kind: "delete", account })}><Trash2 className="h-4 w-4" />Close empty account</button></div></div><div className="space-y-3"><h3 className="text-sm font-semibold">People with access</h3><div className="flex gap-2"><input className="field" value={member} onChange={(event) => setMember(event.target.value)} placeholder="Citizen ID" /><button className="button-secondary" onClick={() => void action({ kind: "addMember", account, citizenid: member })}>Add</button></div><div className="flex flex-wrap gap-2">{(selected.users ?? []).length === 0 ? <span className="text-xs text-muted-foreground">No additional people</span> : selected.users?.map((id) => <button key={id} className="button-ghost border border-border text-xs" onClick={() => void action({ kind: "removeMember", account, citizenid: id })}>{id}<X className="h-3 w-3" /></button>)}</div></div></div> : <p className="py-8 text-center text-sm text-muted-foreground">Select a shared account you own to manage it.</p>}</section>
  </div>
}

function Bank({ snapshot, close, update }: { snapshot: Snapshot; close: () => void; update: (value: Snapshot) => void }) {
  const [view, setView] = useState<View>("activity")
  const [selectedName, setSelectedName] = useState(snapshot.accounts[0]?.name ?? "checking")
  const [error, setError] = useState<string>()
  const selected = snapshot.accounts.find((account) => account.name === selectedName) ?? snapshot.accounts[0]
  const navigation: { id: View; label: string; icon: typeof Landmark }[] = [
    { id: "activity", label: "Activity", icon: Landmark }, { id: "cash", label: "Cash", icon: WalletCards },
    { id: "transfer", label: "Transfer", icon: ArrowRightLeft }, { id: "manage", label: "Manage", icon: Settings },
  ]
  async function run(data: object) {
    setError(undefined)
    try {
      const response = await fetchNui<NuiResult>("qbbanking:action", data)
      if (!response.ok || !response.result) { setError(response.error ?? "The request was declined."); return false }
      update(response.result.snapshot); return true
    } catch { setError("The bank did not answer."); return false }
  }

  return <main className="app-surface flex h-[700px] w-[1120px]">
    <aside className="flex w-[280px] shrink-0 flex-col border-r border-border bg-card">
      <div className="flex items-center gap-3 border-b border-border px-5 py-5"><span className="flex h-10 w-10 items-center justify-center rounded-lg bg-brand-soft text-primary"><Landmark className="h-5 w-5" /></span><div><p className="font-semibold">QBCore Bank</p><p className="text-xs text-muted-foreground">Secure account services</p></div></div>
      <div className="border-b border-border px-5 py-4"><p className="truncate text-sm font-medium">{snapshot.profile.name}</p><p className="mt-1 font-mono text-xs text-muted-foreground">{snapshot.profile.accountNumber}</p><div className="mt-3 flex items-center justify-between text-xs"><span className="text-muted-foreground">Cash on hand</span><span className="font-mono tabular-nums">{money(snapshot.profile.cash)}</span></div></div>
      <div className="scroll-thin flex-1 space-y-2 overflow-y-auto p-3"><p className="px-2 pb-1 pt-2 text-[10px] font-semibold uppercase tracking-[.12em] text-muted-foreground">Your accounts</p>{snapshot.accounts.map((account) => <button key={account.name} onClick={() => { setSelectedName(account.name); setView("activity") }} className={`w-full rounded-lg border p-3 text-left transition-colors ${selected.name === account.name ? "border-brand-border bg-brand-soft" : "border-transparent hover:bg-surface-hover"}`}><span className="flex items-center gap-2 text-xs text-muted-foreground"><AccountIcon type={account.type} />{account.label}</span><span className="mt-1.5 block truncate text-sm font-medium">{account.owner}</span><span className="mt-1 block font-mono text-lg font-semibold tabular-nums">{money(account.balance)}</span></button>)}</div>
      <button className="button-ghost m-3 justify-start" onClick={close}><LogOut className="h-4 w-4" />Sign out</button>
    </aside>
    <section className="flex min-w-0 flex-1 flex-col">
      <header className="flex h-[92px] shrink-0 items-center justify-between border-b border-border px-7"><div><div className="flex items-center gap-2"><span className="rounded bg-brand-soft px-2 py-1 text-[10px] font-semibold uppercase tracking-[.08em] text-primary">{selected.label}</span><span className="text-xs text-muted-foreground">{selected.name}</span></div><h1 className="mt-2 text-xl font-semibold">{selected.owner}</h1></div><div className="flex items-center gap-5"><div className="text-right"><p className="text-xs text-muted-foreground">Available balance</p><p className="font-mono text-2xl font-semibold tabular-nums">{money(selected.balance)}</p></div><CloseButton close={close} /></div></header>
      <nav className="flex shrink-0 gap-1 border-b border-border px-6 py-2">{navigation.map(({ id, label, icon: Icon }) => <button key={id} onClick={() => setView(id)} className={`button-ghost ${view === id ? "bg-brand-soft text-primary" : ""}`}><Icon className="h-4 w-4" />{label}</button>)}</nav>
      <div className="scroll-thin flex-1 overflow-y-auto p-7">{error && <div className="mb-4 flex items-center justify-between rounded-lg border border-destructive/40 bg-destructive/10 px-4 py-3 text-sm"><span>{error}</span><button onClick={() => setError(undefined)}><X className="h-4 w-4" /></button></div>}{view === "activity" && <Activity account={selected} snapshot={snapshot} />}{view === "cash" && <CashForm key={selected.name} account={selected} cash={snapshot.profile.cash} run={run} />}{view === "transfer" && <TransferForm accounts={snapshot.accounts} selected={selected} run={run} />}{view === "manage" && <Manage accounts={snapshot.accounts} maxAccounts={snapshot.limits.maxAccounts} run={run} />}</div>
    </section>
  </main>
}

export default function App() {
  const [snapshot, setSnapshot] = useState<Snapshot>()
  useEffect(() => {
    void fetchNui("qbbanking:ready")
    const message = (event: MessageEvent<{ action?: string; data?: Snapshot }>) => {
      if (event.data?.action === "qbbanking:open" && event.data.data) setSnapshot(event.data.data)
      if (event.data?.action === "qbbanking:close") setSnapshot(undefined)
    }
    const key = (event: KeyboardEvent) => { if (event.key === "Escape") void close() }
    window.addEventListener("message", message); window.addEventListener("keydown", key)
    return () => { window.removeEventListener("message", message); window.removeEventListener("keydown", key) }
  }, [])
  const close = useMemo(() => () => { setSnapshot(undefined); void fetchNui("qbbanking:close") }, [])
  async function runAtm(data: object) {
    const response = await fetchNui<NuiResult>("qbbanking:action", data)
    if (response.ok && response.result) { setSnapshot(response.result.snapshot); return true }
    return false
  }
  return <><ThemeSync /><div className="flex h-full w-full items-center justify-center">{snapshot && (snapshot.locked ? <PinScreen snapshot={snapshot} close={close} unlock={setSnapshot} /> : snapshot.mode === "atm" ? <ATM snapshot={snapshot} close={close} run={runAtm} /> : <Bank snapshot={snapshot} close={close} update={setSnapshot} />)}</div></>
}
