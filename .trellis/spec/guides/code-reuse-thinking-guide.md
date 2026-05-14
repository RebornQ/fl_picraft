# Code Reuse Thinking Guide

> **Purpose**: Stop and think before creating new code - does it already exist?

---

## The Problem

**Duplicated code is the #1 source of inconsistency bugs.**

When you copy-paste or rewrite existing logic:
- Bug fixes don't propagate
- Behavior diverges over time
- Codebase becomes harder to understand

---

## Before Writing New Code

### Step 1: Search First

```bash
# Search for similar function names
grep -r "functionName" .

# Search for similar logic
grep -r "keyword" .
```

### Step 2: Ask These Questions

| Question | If Yes... |
|----------|-----------|
| Does a similar function exist? | Use or extend it |
| Is this pattern used elsewhere? | Follow the existing pattern |
| Could this be a shared utility? | Create it in the right place |
| Am I copying code from another file? | **STOP** - extract to shared |

---

## Common Duplication Patterns

### Pattern 1: Copy-Paste Functions

**Bad**: Copying a validation function to another file

**Good**: Extract to shared utilities, import where needed

### Pattern 2: Similar Components

**Bad**: Creating a new component that's 80% similar to existing

**Good**: Extend existing component with props/variants

### Pattern 3: Repeated Constants

**Bad**: Defining the same constant in multiple files

**Good**: Single source of truth, import everywhere

---

## When to Abstract

**Abstract when**:
- Same code appears 3+ times
- Logic is complex enough to have bugs
- Multiple people might need this

**Don't abstract when**:
- Only used once
- Trivial one-liner
- Abstraction would be more complex than duplication

---

## After Batch Modifications

When you've made similar changes to multiple files:

1. **Review**: Did you catch all instances?
2. **Search**: Run grep to find any missed
3. **Consider**: Should this be abstracted?

---

## Gotcha: Asymmetric Mechanisms Producing Same Output

**Problem**: When two different mechanisms must produce the same file set (e.g., recursive directory copy for init vs. manual `files.set()` for update), structural changes (renaming, moving, adding subdirectories) only propagate through the automatic mechanism. The manual one silently drifts.

**Symptom**: Init works perfectly, but update creates files at wrong paths or misses files entirely.

**Prevention checklist**:
- [ ] When migrating directory structures, search for ALL code paths that reference the old structure
- [ ] If one path is auto-derived (glob/copy) and another is manually listed, the manual one needs updating
- [ ] Add a regression test that compares outputs from both mechanisms

---

## Pattern: Side-Channel Reuse via Repository, Not Controller

**Problem**: You want to reuse a feature's underlying capability (e.g.
"pick an image from gallery") from a different feature, but the existing
feature's top-level Riverpod controller owns **session state** —
selected files, in-progress workflow, etc. Calling the controller would
mutate that state and pollute the original feature's UX. Re-implementing
the capability from scratch duplicates the data-source wiring.

**Solution**: Most feature controllers in this project sit on top of a
**repository** (`*Repository` interface in `domain/repositories/`, impl
in `data/repositories/`). The repository is the stateless capability
surface; the controller adds session state on top. To reuse the
capability without the state, **read the repository provider directly**
and invoke its method — do NOT go through the controller.

```dart
// ❌ WRONG — pollutes the main image-import session
Future<void> pickCenterImage() async {
  final main = ref.read(imageImportControllerProvider.notifier);
  await main.pickFromGallery(limit: 1); // adds to MAIN editor's list!
  final picked = ref.read(imageImportControllerProvider).items.last;
  _setCenterImage(picked);
}

// ✅ CORRECT — side-channel call via repository, isolated state
Future<void> pickCenterImage() async {
  final repo = ref.read(imageImportRepositoryProvider);
  final result = await repo.pickFromGallery(limit: 1);
  // store in THIS controller's state only
  state = state.copyWith(centerImage: result.firstOrNull);
}
```

**Why this works**:
- Repository methods are designed to be stateless / side-effect-free at
  the provider level (no Riverpod state mutation).
- Caller owns the result — the original feature's controller never sees
  the call.
- Testing: the new feature can mock `imageImportRepositoryProvider` in
  isolation; tests don't need to drive the entire main-editor controller.

**When to apply**:
- A feature needs the *capability* of another feature (file picking,
  encoding, network call) but explicitly **not** that feature's session
  state.
- Two parallel sessions of the same workflow need to coexist (e.g. a
  modal "pick another image" while the main gallery has its own list).

**When NOT to apply**:
- You actually want to integrate with the other feature's state (e.g.
  "open the main image-import sheet, then return to me when done"). In
  that case go through its controller and observe its state.
- The capability has no repository abstraction yet — refactor the other
  feature first so the controller sits on a repository, *then* side-
  channel. Don't reach around the controller into a private data source.

---

## Checklist Before Commit

- [ ] Searched for existing similar code
- [ ] No copy-pasted logic that should be shared
- [ ] Constants defined in one place
- [ ] Similar patterns follow same structure
