// approval_card_controller.js
//
// Handles the card flip animation and optimistic UI for approval cards.
//
// When the owner clicks "Send Discount" or "Skip":
//   1. Buttons are disabled immediately (prevents double-submit).
//   2. The card "flips" by hiding the action buttons and showing the
//      confirmation face with a CSS transform (300ms ease-in-out).
//   3. After 800ms, the Turbo Stream response replaces the full card
//      with the compact "done-card" view.
//
// If the server responds with an error (non-2xx), the card reverts.
//
// Targets:
//   card        — the .action-card element (receives the flip class)
//   actions     — the .card-actions div (hidden on flip)
//   confirmation — the confirmation face div (shown on flip)
//   approveBtn  — the approve submit button
//   skipBtn     — the skip submit button
//   confirmIcon — the ✓ or – icon inside the confirmation face

import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["card", "actions", "confirmation", "approveBtn", "skipBtn", "confirmIcon"]

  // Called when the approve form is submitted.
  // Optimistically shows the "approved" confirmation face before the
  // Turbo Stream response arrives.
  approve(event) {
    // Defer animation until after Turbo has captured the form submit event.
    // Disabling the button synchronously in the click handler causes Turbo to
    // lose the submitter reference and fall back to a plain HTML redirect.
    requestAnimationFrame(() => this.#beginTransition("✓"))
  }

  // Called when the skip form is submitted.
  skip(event) {
    requestAnimationFrame(() => this.#beginTransition("–"))
  }

  // ── Private ──────────────────────────────────────────────────────────────

  #beginTransition(icon) {
    // Disable buttons to prevent double-submit
    this.#setButtonsDisabled(true)

    // Update confirmation icon
    if (this.hasConfirmIconTarget) {
      this.confirmIconTarget.textContent = icon
    }

    // Animate: fade out actions, fade in confirmation
    if (this.hasActionsTarget) {
      this.actionsTarget.style.transition = "opacity 200ms ease-out"
      this.actionsTarget.style.opacity = "0"
    }

    // After 200ms, hide actions and reveal confirmation
    setTimeout(() => {
      if (this.hasActionsTarget) {
        this.actionsTarget.style.display = "none"
      }
      if (this.hasConfirmationTarget) {
        this.confirmationTarget.style.display = "block"
        this.confirmationTarget.style.opacity = "0"
        this.confirmationTarget.style.transition = "opacity 250ms ease-in"
        // Trigger reflow then fade in
        void this.confirmationTarget.offsetWidth
        this.confirmationTarget.style.opacity = "1"
      }
    }, 200)

    // After 800ms, apply a subtle scale-down to signal the card is collapsing
    // (the Turbo Stream replacement will complete the transition)
    setTimeout(() => {
      if (this.hasCardTarget) {
        this.cardTarget.style.transition = "opacity 300ms ease-in, transform 300ms ease-in"
        this.cardTarget.style.opacity = "0.6"
        this.cardTarget.style.transform = "scale(0.97)"
      }
    }, 800)
  }

  #setButtonsDisabled(disabled) {
    if (this.hasApproveBtnTarget) {
      this.approveBtnTarget.disabled = disabled
    }
    if (this.hasSkipBtnTarget) {
      this.skipBtnTarget.disabled = disabled
    }
  }
}
