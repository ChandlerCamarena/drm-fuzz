# DRM/KMS Kernel Fuzzing

**Coverage-guided vulnerability research against the Linux kernel's Direct
Rendering Manager (DRM) subsystem**, progressing from a hardware-free
virtual driver to real GPU hardware, built on syzkaller, KASAN, and KCOV,
with a fully reproducible Nix-based environment.

---

## Summary

The DRM/KMS ioctl interface is the boundary between unprivileged userspace
and kernel-level GPU driver code. It parses attacker-influenced structures
on every mode-set, buffer allocation, and command submission — a well
established, still-productive class of kernel attack surface, and one with
a direct real-world escalation path: a memory-safety bug here is not a
crashed process, it is potential kernel-level compromise from an
unprivileged caller.

This project builds a reproducible research pipeline for finding such bugs:
an instrumented kernel (KASAN for detection, KCOV for coverage-guided
fuzzing feedback), syzkaller as the fuzzing engine, and a staged target
progression — from VKMS (a safe, in-tree virtual driver built for exactly
this kind of testing) to i915 (this machine's real Intel integrated GPU
driver), with Nouveau as a stretch target. Findings are triaged,
root-caused, and — where real — disclosed responsibly before any public
detail is published.

The environment itself is the first deliverable: `nix develop` plus two
scripts reproduce the exact toolchain, exact kernel version, and exact
kernel configuration on any machine, from a clean checkout, with no
undocumented manual steps.

---

## Why this project, and why it's structured this way

Kernel fuzzing campaigns are frequently under-documented and
non-reproducible — a `.config` file with unexplained flags, a kernel
version nobody recorded, a toolchain nobody pinned. That's a real problem
for a research artifact meant to be reviewed, extended, or trusted: an
unreproducible result is a claim, not evidence.

Every design decision here optimizes for the opposite: **anyone should be
able to arrive at the identical environment this research was conducted
in, from a clean machine, using only what's committed to this repository.**
That standard shapes the toolchain choices below as much as the fuzzing
methodology itself.

---

## Toolchain

| Component | Purpose | Why it's here |
|---|---|---|
| **Nix (flakes)** | Pins the entire build toolchain — compiler, QEMU, Go, kernel build dependencies — to exact versions via `flake.nix` / `flake.lock`. | Removes "works on my machine" ambiguity entirely; the dev shell is byte-for-byte reproducible, not just documented. |
| **Linux kernel, pinned to `v7.2`** | The fuzzing target. | A named, citable release rather than a moving `HEAD` — essential for any finding to be reproducible against a known baseline. |
| **KASAN** (generic, inline) | Converts silent memory-safety violations — out-of-bounds access, use-after-free — into immediate, symbolized kernel panics. | Without this, a fuzzer can trigger a real bug and observe nothing; KASAN is what makes a bug *detectable* at all, not just triggerable. Inline mode trades build time for faster execution, the right tradeoff for long-running campaigns. |
| **KCOV** (`INSTRUMENT_ALL`) | Per-syscall code-coverage tracking, consumed by syzkaller as its exploration signal. | This is what makes the fuzzing *coverage-guided* rather than blind — inputs that reach new code get prioritized for further mutation, which is the entire reason coverage-guided fuzzing outperforms random fuzzing in practice. |
| **DEBUG_INFO / DWARF4** | Embeds source-line debug information in the build. | Turns a KASAN crash report from a bare, useless address into a file, line, and function — the difference between a finding you can root-cause and one you can't. |
| **syzkaller** | The fuzzing engine (Google). Generates structured syscall inputs, mutates them under KCOV feedback, detects and triages crashes. | Purpose-built, actively maintained, the standard tool for exactly this class of research. |
| **QEMU** | Runs the instrumented kernel in isolation. | Fuzzing-induced kernel panics and memory corruption stay contained to the VM — never the host. |
| **DRM_VKMS** (module) | Virtual, hardware-free DRM driver; upstream's own purpose-built testing target. | Validates the entire pipeline — kernel, KASAN, KCOV, syzkaller, syscall descriptions — with zero hardware risk before any real driver is touched. |
| **DRM_I915** (module) | Intel integrated graphics driver. | Confirmed as this machine's actual bound display driver (`lspci -k` → `Kernel driver in use: i915`, Raptor Lake UHD Graphics 770) — the real-hardware phase of this research. |

---

## Scope

**In scope:** VKMS (primary target, validates methodology), i915 (real
hardware, primary research target), Nouveau (stretch — architecturally
distinct target on the machine's RTX 4080).

**Explicitly out of scope:** NVIDIA's proprietary driver. It is closed
source — there is no way to root-cause a crash against it, no way to build
it into an instrumented in-tree kernel the way KASAN/KCOV require, and its
disclosure process is opaque relative to upstream kernel maintainers.
Nouveau is the deliberate, open-source substitute for this hardware.

Documenting what's excluded, and why, is treated as part of the
methodology — a scope boundary stated up front is a design decision, not
an oversight discovered later.

---

## Repository layout

```text
drm-fuzz/
├── flake.nix                  # Reproducible environment definition
├── flake.lock                 # Exact pinned versions of all Nix inputs
├── install.sh                 # Top-level orchestrator: setup -> build -> build-rootfs
├── syzkaller-config-vkms.cfg  # syz-manager config for the VKMS target
├── README.md
├── scripts/
│   ├── setup.sh            # Clones pinned kernel, applies config
│   ├── build.sh            # Builds the configured kernel
│   ├── build-rootfs.sh     # Orchestrates full rootfs build unattended
│   ├── patch-rootfs.sh     # Applies required fixes to syzkaller's rootfs image
│   └── kernel.config       # This project's config additions (fragment)
├── linux/                  # Reproduced by setup.sh — not tracked
├── syzkaller/              # Cloned/built separately — not tracked
└── workdir/                # syz-manager output: corpus, crashes, VM state — not tracked
```

The kernel source, syzkaller, and the fuzzing workdir are intentionally
excluded from version control. The kernel and syzkaller are large,
independently-versioned repositories in their own right; tracking them
directly would bloat this repository indefinitely and create
nested-repository ambiguity for no benefit. The workdir is pure generated
output — corpus, crash logs, VM disk state — that changes on every run and
carries no value as a tracked artifact. Instead, the scripts that
*reconstruct* the toolchain exactly are what's tracked — the
reproducibility guarantee lives in code, not in a committed binary
artifact.

`syzkaller-config-vkms.cfg` is tracked: it is small, hand-written, and is
the actual specification of how the fuzzer is invoked (VM count, memory,
target syscalls, image/kernel paths). Note that its path fields are
machine-specific and will need adjusting to your own checkout location.

---

## Quick start

```bash
nix develop
bash scripts/setup.sh
bash scripts/build.sh
```

`setup.sh`:
1. Shallow-clones the kernel directly at tag `v7.2`.
2. Generates a baseline x86_64 config, merges KVM-guest defaults.
3. Merges this project's config fragment via the kernel's own
   `merge_config.sh`, logging every overridden value for auditability.
4. Resolves all resulting dependencies (`make olddefconfig`).
5. Prints a verification grep of every target config value.

`build.sh` compiles the result, producing
`linux/arch/x86/boot/bzImage` — the bootable image used in the QEMU phase.

### A known, non-fatal warning

The clone step prints:

warning: refs/tags/v7.2 <hash> is not a commit!

Expected: `v7.2` is an *annotated* tag, and Git's shallow-fetch path
resolves annotated tags indirectly, producing this warning even on a
fully correct checkout. Independently verified via `git describe --tags`
(returns exactly `v7.2`, no offset) and `git log -1` (shows Linus
Torvalds' own "Linux 7.2" tagging commit). Documented here so it reads as
a known artifact of the tooling, not a silent, unexplained anomaly.

---

## Booting the kernel in QEMU

After `syzkaller/tools/create-image.sh` produces `trixie.img`, apply the
required rootfs patches (see below) and boot with:

```bash
qemu-system-x86_64 \
  -kernel linux/arch/x86/boot/bzImage \
  -drive file=syzkaller/tools/trixie.img,format=raw \
  -append "console=ttyS0 root=/dev/sda earlyprintk=serial net.ifnames=0 selinux=0" \
  -netdev user,id=net0,hostfwd=tcp::10021-:22 \
  -device e1000,netdev=net0 \
  -nographic \
  -m 2G \
  -smp 2 \
  -enable-kvm
```

SSH into the running guest via the forwarded port:

```bash
ssh -i syzkaller/tools/trixie.id_rsa -p 10021 root@localhost
```

### Required rootfs patch

`syzkaller/tools/create-image.sh` builds a rootfs with defaults that
don't match this project's minimal kernel config. Run once, after every
fresh `create-image.sh`:

```bash
bash scripts/patch-rootfs.sh
```

This applies three fixes:
1. **Removes the `configfs` fstab entry.** The kernel isn't built with
   `CONFIG_CONFIGFS_FS` (unused subsystem for this project — USB gadget
   mode, some netfilter targets); without this, boot fails into
   emergency mode via a `local-fs.target` dependency cascade.
2. **Disables SELinux** (`/etc/selinux/config`). Not needed for a
   fuzzing target and reduces log noise around crash triage. Paired with
   `selinux=0` on the kernel command line above.
3. **Symlinks `ssh.service` into `multi-user.target.wants`.**
   `create-image.sh` doesn't enable it by default; syzkaller's manager
   drives the guest over SSH.

`CONFIG_SECURITYFS=y` is set directly in `scripts/kernel.config` rather
than patched out of the rootfs, since securityfs is exposed to
security-relevant kernel state (LSM/IMA-adjacent interfaces) that's worth
keeping present for this class of research, unlike configfs.

---

## Running the fuzzer

```bash
./syzkaller/bin/syz-manager -config=syzkaller-config-vkms.cfg
```

Do **not** add `-debug` for a real fuzzing run: debug mode silently caps
VM count to 1 regardless of the config's `vm.count` value. The web UI
(address/port set in the config) shows live corpus size, coverage, crash
counts, and per-VM status while the manager runs.

---

## Operational safety

VKMS fuzzing is inherently contained — it runs entirely inside the QEMU
guest against a virtual driver, with no path to the host.

i915 is not contained the same way: it is this machine's actual, live
display driver (`lspci -k` confirms binding). Fuzzing it therefore carries
real risk to the host's active session. That phase will run from a
non-graphical TTY, or preferably on separate/headless hardware — never
interactively on the primary desktop session — so an in-progress kernel
panic cannot take down the working environment mid-campaign. This
decision is recorded here before that phase begins, not reconstructed
after an incident.

---

## Hardware baseline

- **iGPU:** Intel Raptor Lake-S, UHD Graphics 770 — `i915`, confirmed
  bound and active.
- **dGPU:** NVIDIA RTX 4080 — `nvidia`/`nvidia_drm`, proprietary, out of
  scope (see Scope).
- Hybrid graphics confirmed active (both GPUs simultaneously live) via
  `lspci | grep -iE "vga|3d|display"` and `lsmod`.

---

## Status

- [x] Reproducible Nix environment (`flake.nix` / `flake.lock`)
- [x] Kernel pinned to `v7.2`; KASAN, KCOV, DRM_VKMS, DRM_I915 configured
      and verified via automated script, not manual steps
- [x] Kernel builds successfully under this configuration
- [x] QEMU boot + minimal rootfs
- [x] syzkaller operational against VKMS: 4-VM parallel fuzzing,
      corpus/coverage growing, crashes captured
- [ ] Crash triage: root-cause each distinct crash type found so far
      (not yet started — toolchain validation was the priority for this
      milestone)
- [ ] Coverage-vs-source cross-reference: confirm fuzzing is exercising
      VKMS-specific code paths, not just generic DRM ioctl dispatch
- [ ] Extend DRM syscall descriptions for VKMS coverage gaps, if the
      cross-reference above surfaces any
- [ ] Pivot to i915 (real hardware; see Operational Safety)
- [ ] Stretch: Nouveau
- [ ] `--target=vkms|i915|4080` flag: a single entry point selecting which
      driver to fuzz, rather than separate manual configs per target (see
      Future Work)
- [ ] Responsible disclosure where applicable; final technical writeup

---

## Future work

**Unified target selection.** Currently, switching between VKMS and a
real-hardware target (i915, eventually the 4080 via Nouveau) means
maintaining separate syzkaller configs, separate rootfs states, and
separate operational-safety postures by hand. The plan is a single
`--target` flag (e.g. `--target=vkms`, `--target=i915`, `--target=4080`)
that selects the correct syzkaller config, kernel module set, and safety
constraints (VM-contained vs. real-hardware-with-isolation) automatically
— reducing the current manual, per-target setup to one command and
removing an entire class of "wrong config for this target" mistakes.

---

## Author background

This project is part of a portfolio oriented toward Linux graphics driver
and kernel-security engineering. Related background: MSc in Computer
Science, Cybersecurity specialization, Eötvös Loránd University (Fulbright
Open Research/Study Award), and prior static-analysis tooling work — a
Clang-Tidy checker detecting padding-byte information leakage at annotated
trust boundaries, accompanying an MSc thesis under Dr. Zoltán Porkoláb.
That project demonstrated static, compile-time analysis rigor; this one is
its dynamic-analysis counterpart — the same standard of methodology and
reproducibility, applied to fuzzing instead of static checking.
