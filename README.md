# zora - a lightweight graphics abstraction layer
## ⚠️ **This project is in an early stage of development.**

`zora` is a graphics abstraction layer built to be fast, easy to use and maintain. 

`zora` aims to build a stable framework baseline by only providing **bare minimum modern features** (roughly equavalent to `Vulkan 1.0` / `OpenGL 4.0`) to keep project's scope clear and maintainable, taking heavy inspiration from modern **GAL**s like `SDL_GPU` and `WebGPU`. 

It is built using **[Zig Programming Language](https://ziglang.org/)**.

## 📋 Who is it built for?
`zora` is built for people that **just want to see something on the screen, no matter what.** While you cannot do ray-tracing using `zora`, it is **complex enough** to **allow most common rendering techniques** (ex. instancing, batching).

## ⭐ Features
- **Easy to use** -- it skips over the **boring part** (ex. enumerating extensions, querying adapters, etc...) and **lets you do your work**.
- **Little to no memory allocations** -- **it doesn't allocate anything on heap**, but the underlying backend might.
- **Little to no overhead** -- **the abstraction layer is kept as thin as possible** by utilizing Zig's numerous features.

## 🔧 Supported backends
`zora` aims to cover **at least 95%** of the all hardware on the market, as such backends chosen here represent different goals.
- 🚧 `Vulkan` 1.0 -- Modern option for desktop and mobile.
- 📅 `OpenGL` 3.3+ -- Battle-tested classic, runs on practically anything.
- 📅 `OpenGLES` 2.0+ -- Good support for mobile, web (`WebGL`) and embedded.

## 🖥️ Supported platforms
### 🥇 Tier 1
Platforms that are actively supported and tested:
  - `GNU/Linux`
  - `Android`
  - `FreeBSD`
  - `Microsoft Windows 10+`
### 🥈 Tier 2
Platforms that I have limited access to:
  - `macOS`
  - `iOS`
  - `OpenBSD`
  - `NetBSD`

## ⛓️‍💥 Known limitations
### Initialization code is heavy on stack
On some backends (like Vulkan), `zora` **internally pre-allocates a significant amount of space on stack upfront**. Depending on amount of stack space available during initialization phase, this could be a massive limitation. 

**It's recommended that you initialize `zora` first before doing heavy stack allocations.** 

### Reliance on `GLSL`
**This is not an issue if you're only targetting** `Vulkan`, but is still a notable limitation.

**The most straightforward way** to write shaders for `zora` is to use **OpenGL Shading Langauge**. 

While not strictly required, some of the backends **historically support SPIR-V poorly** (`OpenGL` 4.5+) or **simply don't at all** (`OpenGL` < 4.5, `OpenGLES`), as such `zora` provides an ***optional*** way to attach `GLSL` text shader source.

## ❓ FAQ
### When will `zora` be ready?
I will start tagging releases as the library grows closer to 1.0 release.

### Is `zora` development powered by AI/LLMs/Agents?
**No,** it is being developed by an **unemployed 20 year old guy**. You choose what's worse.
