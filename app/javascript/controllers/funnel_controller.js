import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = [ "stage", "panel" ]

  toggle(event) {
    const key = event.currentTarget.dataset.stageKey
    const wasPressed = event.currentTarget.getAttribute("aria-pressed") === "true"
    this.stageTargets.forEach((stage) => stage.setAttribute("aria-pressed", "false"))
    if (!wasPressed) event.currentTarget.setAttribute("aria-pressed", "true")
    this.panelTargets.forEach((panel) => {
      panel.hidden = panel.dataset.stagePanel !== key || wasPressed
    })
  }
}
