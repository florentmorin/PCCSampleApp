# Sample code PCC

Ugly code used to for conditional compilation demo.

How to add a condition on compilation based on OS version?

```swift
#if canImport(FoundationModels, _version: 2.0)
// SDK 27.0 code
#else
// SDK < 27.0 code
#endif

```

How to detect OS version at runtime?

```swift
if #available(anyAppleOS 27.0, *) {
    // OS 27.0 code
} else {
    // OS < 27.0 code
}

```
