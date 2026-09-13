# Quickstart

Point it at a PDF and let it ask how you want it:

```vim
:PdfPort
```

The mode picker is the same one every integration shows, and "system
application" is always one of the choices. Then, when you already know:

```vim
:PdfPort text       " extract into a buffer
:PdfPort float      " into a floating window, prompting for a page range
:PdfPort terminal   " as a terminal image, same prompt
:PdfPort system     " hand it to the system application
:PdfPort backends   " which backends are registered, and which resolve right now
```

And the other direction:

```vim
:PdfPort create                                    " a PDF from an image, Markdown, text, HTML or Office file
:PdfPort merge out.pdf a.pdf b.pdf                 " two or more into one
:PdfPort producers                                 " which producers resolve right now
```

Verify your setup any time with:

```vim
:checkhealth pdfport
```

See [what-you-get.md](what-you-get.md) for the rest of the surface at a
glance, or [commands.md](commands.md) for the full reference.
