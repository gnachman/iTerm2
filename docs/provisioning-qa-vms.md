# Provisioning QA VMs (agent guide)

There is a small fixed pool of virtual machines that agents use for QA. Because
several agents run at once, you cannot just pick a VM: you must reserve one so
two agents never use the same VM at the same time. This guide explains how to
reserve a VM, use it, and return it.

The tooling is three commands in `~/bin`:

- `vm-reserve` - claim a free VM for your process
- `vm-return` - release a VM before your process exits
- `vm-status` - show the pool and who holds what

All three are the same program (`vm-pool`) invoked under different names.

## The one rule: reservations are tied to a process

A reservation is owned by a process ID. **It ends automatically when that
process exits.** You pass your own PID when you reserve; if you crash or forget
to return the VM, the next agent that reserves or checks status reaps your dead
reservation and the VM becomes free again. Nothing leaks.

This means you normally do not even need `vm-return`: reserve against a PID that
lives exactly as long as you need the VM, and it is released when that process
goes away. Return early only when you finish well before your process exits.

## Reserve a VM

```sh
vm=$(vm-reserve --pid $$) || exit 1
echo "reserved $vm"
```

`vm-reserve` prints the reserved VM's identifier (a hostname, IP, or ssh alias;
see Configuration below) to stdout and nothing else, so you can capture it in a
variable. Diagnostics go to stderr.

- `--pid PID` (required): the process that owns the reservation. Use `$$` for
  the current shell, or the PID of whatever long-lived process represents your
  session. Reserving against a PID that is not running is rejected, because the
  reservation would be reclaimed immediately.
- If no VM is free, `vm-reserve` fails with a nonzero exit status and does not
  block. Always check the exit status.

### Block until a VM is free

```sh
vm=$(vm-reserve --pid $$ --wait) || exit 1
```

- `--wait`: instead of failing when the pool is full, wait until a VM frees up.
- `--timeout SECONDS`: with `--wait`, give up after this long (nonzero exit).
- `--interval SECONDS`: with `--wait`, how often to retry (default 2).

### Label a reservation

```sh
vm=$(vm-reserve --pid $$ --label "issue 13108") || exit 1
```

`--label` is free text shown in `vm-status`, handy for seeing what each VM is
being used for.

## Return a VM

Returning is optional (the reservation ends when your process exits), but do it
when you finish early so others can use the VM sooner.

```sh
vm-return "$vm"        # return a specific VM by identifier
vm-return --pid $$     # return every VM this process holds
```

Returning a VM by name works regardless of who owns it. If you pass both a VM
name and `--pid`, it refuses to return a VM owned by a different PID (a guard
against returning someone else's VM by mistake).

## Check status

```sh
vm-status            # human-readable
vm-status --json     # machine-readable
```

Status lists every VM in the pool as free or reserved, and for reserved VMs
shows the owning PID, label, reservation time, and host. Running it also reaps
any dead reservations.

## A typical agent recipe

```sh
# Wait up to 10 minutes for a VM, fail if none shows up.
vm=$(vm-reserve --pid $$ --wait --timeout 600 --label "QA: $TASK") || {
  echo "no QA VM available" >&2
  exit 1
}

# ... run QA against "$vm" ...

vm-return "$vm"      # optional; happens automatically when this process exits
```

## Configuration

The pool is a config file, one VM identifier per line; blank lines and `#`
comments are ignored:

```
~/.config/vm-pool/pool
```

Put whatever an agent should connect to on each line (hostname, IP address, or
an ssh alias from `~/.ssh/config`). Whatever is on the line is exactly what
`vm-reserve` prints. To add or remove a VM from rotation, edit this file; no
restart is needed.

Reservation state lives under `~/.local/state/vm-pool/`. Both locations can be
overridden with the `VM_POOL_CONFIG` and `VM_POOL_STATE` environment variables
(useful for testing against a throwaway pool).

## How it works

- Allocation is guarded by an exclusive file lock, so concurrent `vm-reserve`
  calls never hand the same VM to two agents. The lock is held only during
  allocation, not while `--wait` sleeps between retries.
- Liveness is checked with a signal-0 probe (`kill(pid, 0)`). Every operation
  reaps reservations whose owner has died before deciding what is free.
- A single process may hold more than one VM; each `vm-reserve` grabs one more.
  `vm-return --pid` releases all of them at once.
