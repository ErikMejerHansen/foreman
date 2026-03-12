const ImagePasteHook = {
  mounted() {
    this.images = []
    this.container = document.getElementById("task-images-container")

    this.pasteHandler = (e) => {
      const items = e.clipboardData?.items
      if (!items) return

      const imageItems = Array.from(items).filter(item => item.type.startsWith("image/"))
      if (imageItems.length === 0) return

      e.preventDefault()

      imageItems.forEach(item => {
        const file = item.getAsFile()
        if (!file) return

        const reader = new FileReader()
        reader.onload = (event) => {
          const dataUrl = event.target.result
          // dataUrl is "data:image/png;base64,<data>"
          const [header, data] = dataUrl.split(",")
          const mediaType = header.match(/data:([^;]+)/)[1]
          const index = this.images.length
          this.images.push({ data, media_type: mediaType })
          this.pushEvent("paste_image", { data, media_type: mediaType })
          this.addPreview(dataUrl, index)
        }
        reader.readAsDataURL(file)
      })
    }

    this.el.addEventListener("paste", this.pasteHandler)

    this.handleEvent("clear_images", () => {
      this.images = []
      if (this.container) this.container.innerHTML = ""
    })
  },

  addPreview(dataUrl, index) {
    if (!this.container) return

    const wrapper = document.createElement("div")
    wrapper.className = "relative group"
    wrapper.dataset.index = index

    const img = document.createElement("img")
    img.src = dataUrl
    img.className = "h-20 w-20 object-cover rounded border border-base-300"

    const btn = document.createElement("button")
    btn.type = "button"
    btn.textContent = "×"
    btn.className = "absolute -top-1 -right-1 bg-error text-error-content rounded-full w-5 h-5 text-xs hidden group-hover:flex items-center justify-center leading-none"
    btn.addEventListener("click", () => {
      const idx = parseInt(wrapper.dataset.index)
      this.images.splice(idx, 1)
      this.pushEvent("remove_image", { index: idx })
      wrapper.remove()
      // Reindex remaining previews
      Array.from(this.container.children).forEach((child, i) => {
        child.dataset.index = i
      })
    })

    wrapper.appendChild(img)
    wrapper.appendChild(btn)
    this.container.appendChild(wrapper)
  },

  destroyed() {
    this.el.removeEventListener("paste", this.pasteHandler)
  }
}

export default ImagePasteHook
