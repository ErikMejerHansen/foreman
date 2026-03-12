const ImagePasteHook = {
  mounted() {
    this.images = []

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
          this.images.push({ data, media_type: mediaType })
          this.pushEvent("paste_image", { data, media_type: mediaType })
        }
        reader.readAsDataURL(file)
      })
    }

    this.el.addEventListener("paste", this.pasteHandler)

    this.handleEvent("clear_images", () => {
      this.images = []
    })
  },

  destroyed() {
    this.el.removeEventListener("paste", this.pasteHandler)
  }
}

export default ImagePasteHook
