import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = [ "dialog", "confirm" ]

  open(event) {
    event.preventDefault()
    this.form = event.currentTarget.form
    this.dialogTarget.showModal()
    this.confirmTarget.focus()
  }

  confirm() {
    this.dialogTarget.close()
    this.form?.requestSubmit()
  }

  close() {
    this.dialogTarget.close()
  }
}
