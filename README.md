# ✈️ X-Pilot Remote (iPhone Autopilot for X-Plane)

[![Swift 6.0](https://img.shields.io/badge/Swift-6.0-orange.svg)](https://swift.org)
[![Platform](https://img.shields.io/badge/Platform-iOS%2017%2B-blue.svg)](https://apple.com)
[![X-Plane](https://img.shields.io/badge/Simulator-X--Plane%2011%2F12-blue.svg)](https://x-plane.com)
[![License](https://img.shields.io/badge/License-MIT-green.svg)](LICENSE)

**X-Pilot Remote** transforms your iPhone into a dedicated physical autopilot interface for X-Plane. Manage heading, altitude, and GPS navigation without touching your mouse or breaking immersion in the virtual cockpit. Tested on Xplane 12 only.

---

## 🚀 Key Features

- **Real-time Synchronization:** Low-latency bidirectional communication via UDP protocol (X-Plane DataRefs).
- **Full AFCS Control:**
  - Heading (**HDG**) and Navigation (**NAV**) selectors.
  - Altitude (**ALT**) and Vertical Speed (**VS**) management.
  - Autopilot and Flight Director toggles.
- **Authentic Visual Feedback:** High-fidelity replication of Garmin G1000 status logic (e.g., Armed modes in white, Active modes in green).
- **Haptic Interface:** Physical vibration feedback for knob turns and button presses, designed for "blind" operation during flight.



---

## 🛠 Tech Stack

- **Language:** Swift 6.0 (utilizing modern Concurrency/Actors).
- **UI:** SwiftUI with custom glassmorphic components.
- **Networking:** Apple's `Network.framework` for efficient UDP packet handling.
- **AI-Assisted:** Developed and optimized using Gemini 3 Flash for architectural patterns.

---

## 📦 Quick Start

1. **Clone the repository:**
   ```bash
   git clone [https://github.com/mava70/xplane-ios-autopilot.git](https://github.com/mava70/xplane-ios-autopilot.git)
