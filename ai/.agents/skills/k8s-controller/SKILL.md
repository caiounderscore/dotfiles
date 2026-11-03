---
name: k8s-controller
description: Checklist for writing or changing a Kubernetes controller or operator built on controller-runtime or kubebuilder, covering reconcile shape, finalizers, ownership, status conditions, requeue, API changes, and envtest. Use when editing a Reconcile function, CRD types, webhooks, or operator RBAC.
---

# Kubernetes controller changes

## Reconcile shape

- Reconcile is level-triggered: read the current state, compute the desired state, and converge. Never depend on
  which event triggered the call.
- Return nil when the object is gone. Handle deletion first: while `DeletionTimestamp` is set, clean up, then remove
  the finalizer. Add the finalizer before creating anything outside the cluster.
- Never mutate the `.spec` of the object being reconciled; write `.status` through the status subresource only.
- Give children deterministic names and owner references (`controllerutil.SetControllerReference`), so a retry
  converges instead of creating a duplicate.
- Prefer `controllerutil.CreateOrPatch` or server-side apply with one fixed field manager over get-then-create.
  Treat `AlreadyExists` and `Conflict` as retryable.
- Return an error for retryable failures and let controller-runtime back off. For a permanent spec error, set a
  condition and return nil instead of hot-looping. Use `RequeueAfter` only to poll state outside the cluster.

## Status

- Use `metav1.Condition` through `meta.SetStatusCondition` with stable `Type` and `Reason` values, and set
  `ObservedGeneration` on each condition.
- Write status only when it changed, so the controller does not trigger itself.
- Watch owned objects with `Owns` instead of polling them.

## API and RBAC

- New CRD fields are optional with a default, so existing objects stay valid. Never repurpose a field.
- Regenerate with the repository's generator target and review the generated diff together with the handwritten one.
- Keep RBAC markers to the verbs the code uses.

## Tests

- Test at the reconciler seam with envtest: create the object, then assert children and conditions with `Eventually`.
- Cover create, update, deletion with the finalizer, a child deleted out of band, an update conflict, and a
  permanent spec error.
- Run `go test -race` and the repository's lint target.
