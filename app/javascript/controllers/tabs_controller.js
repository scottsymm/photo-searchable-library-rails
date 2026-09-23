import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = [ "tab", "panel" ]

  select(event) {
    const key = event.currentTarget.dataset.tabKey
    this.tabTargets.forEach((tab) => {
      tab.setAttribute("aria-selected", tab.dataset.tabKey === key ? "true" : "false")
    })
    this.panelTargets.forEach((panel) => {
      panel.hidden = panel.dataset.panelKey !== key
    })
  }
}
