This is my final year project. This project is definitely not a good project and i am still trying to learn more in software engineering

# Smart Hostel Energy Monitor & Disaggregation System

A Non-Intrusive Load Monitoring (NILM) platform that disaggregates aggregate smart meter readings into individual appliance profiles using a Factorial Hidden Markov Model — no sub-metering hardware required.

---

## Table of Contents

- [Overview](#overview)
- [Problem Statement](#problem-statement)
- [Solution](#solution)
- [Features](#features)
- [Architecture](#architecture)
- [Technology Stack](#technology-stack)
- [Project Structure](#project-structure)
- [Getting Started](#getting-started)
  - [Prerequisites](#prerequisites)
  - [Backend Setup](#backend-setup)
  - [Frontend Setup](#frontend-setup)
- [Usage](#usage)
- [License](#license)

---

## Overview

Institutional student hostels have limited visibility into how electricity is actually being consumed. Without knowing which appliances are drawing power — and how much — facility managers cannot enforce safety policies, prevent grid overloads, or hold residents accountable for excessive usage.

Installing individual sub-meters at every outlet solves the visibility problem but creates a new one: prohibitive hardware costs, ongoing maintenance, and complex network deployment at scale.

This project takes a software-first approach. By analyzing the aggregate power signal from a single smart meter, the system mathematically separates overlapping appliance signatures and reconstructs individual consumption profiles. Students can register their devices for monitoring, while administrators review and authorize them through a real-time dashboard.

---

## Problem Statement

Conventional power monitoring in hostel environments requires physical sub-metering hardware at every socket — an approach that does not scale. Beyond the financial overhead, facility managers lack a centralized mechanism to:

- Verify device compliance against safety and usage policies
- Identify prohibited high-load appliances (e.g., kettles, irons, space heaters)
- Detect anomalous or sustained power draw from individual rooms

The result is unchecked electrical waste, unaccounted utility costs, and latent safety risks.

---

## Solution

This system replaces hardware sub-metering with a software disaggregation pipeline:

- **NILM-based load disaggregation** — A Factorial Hidden Markov Model (FHMM) separates overlapping appliance power profiles from a single meter feed, isolating individual device consumption without additional hardware.
- **Administrative oversight** — A real-time dashboard enables facility managers to review registered appliances, route items through a validation queue, and authorize or restrict devices instantly.
- **Cross-platform client** — A Flutter mobile application allows students to register appliances and view their consumption analytics, with state synchronization handled end-to-end through the cloud backend.

---

## Features

- **Multi-state load disaggregation** using `GaussianHMM` emission parameters to model appliance power states
- **Zero-cold-start initialization** — appliance profiles are loaded directly into model states at runtime, eliminating warm-up delay
- **Asynchronous REST API** built with FastAPI and validated through Pydantic schema definitions
- **Real-time admin dashboard** with explicit state transitions and item-level validation routing
- **Reactive mobile UI** powered by Flutter's Provider state management pattern
- **Cloud-native deployment** on Google Cloud Run with structured logging via a custom `AppLog` architecture

---

## Architecture

The system is organized into four layers, each with a distinct responsibility:

```
[Client Layer]
  Flutter mobile app handles appliance registration,
  consumption chart retrieval, and user authentication flows.
        │
        ▼
[API / Backend Layer]
  FastAPI service receives telemetry payloads, validates request
  structures via Pydantic schemas, and routes to business logic.
        │
        ▼
[Business Logic Layer]
  FHMM execution block loads pre-trained device vectors,
  runs Viterbi decoding, and outputs per-appliance state sequences.
        │
        ▼
[Database / Cloud Layer]
  Firestore persists usage metrics, appliance documents,
  and admin queue state across sessions.
```

The backend is containerized and deployed to Google Cloud Run in the `asia-southeast1` region. All inter-layer communication is stateless; Firestore serves as the single source of truth for shared application state.

---

## Technology Stack

| Layer | Technology |
|---|---|
| Mobile Frontend | Flutter 3.x (Dart) |
| Backend API | FastAPI, Uvicorn (Python) |
| ML Library | `hmmlearn` |
| Database | Google Cloud Firestore |
| Cloud Runtime | Google Cloud Run |
| Containerization | Docker (multi-stage build) |
| Observability | Google Cloud Logging |

---

## Project Structure

```
smart-meter-project/
│
├── mlbackend/                  # Machine learning service
│   ├── config/                 # Logging and environment configuration
│   ├── models/                 # Pydantic request/response schemas
│   ├── services/               # FHMM logic and Firestore interactions
│   ├── main.py                 # FastAPI app entry point and route definitions
│   └── Dockerfile              # Multi-stage production container
│
├── smartmeter/                 # Flutter mobile application
│   ├── assets/                 # Fonts and static media
│   ├── lib/
│   │   ├── config/             # Global UI theme and styling constants
│   │   ├── controllers/        # Provider state management and API clients
│   │   ├── models/             # Dart deserialization models
│   │   └── screens/            # UI screens and widget components
│   └── pubspec.yaml            # Dart package dependencies
│
└── README.md
```

---

## Getting Started

### Prerequisites

- Python 3.10+
- Flutter SDK 3.x
- Docker
- A Google Cloud project with Firestore enabled and a valid service account key

### Backend Setup

1. Navigate to the backend directory:

   ```bash
   cd mlbackend
   ```

2. Create and activate a virtual environment:

   ```bash
   python -m venv venv
   source venv/bin/activate       # On Windows: venv\Scripts\activate
   ```

3. Install dependencies:

   ```bash
   pip install -r requirements.txt
   ```

4. Set required environment variables:

   ```bash
   export GOOGLE_APPLICATION_CREDENTIALS="path/to/service-account.json"
   ```

5. Start the development server:

   ```bash
   uvicorn main:app --reload
   ```

To build and run via Docker:

```bash
docker build -t smart-meter-backend .
docker run -p 8080:8080 smart-meter-backend
```

### Frontend Setup

1. Navigate to the Flutter project directory:

   ```bash
   cd smartmeter
   ```

2. Install dependencies:

   ```bash
   flutter pub get
   ```

3. Update the API base URL in `lib/config/` to point to your backend instance.

4. Run the application:

   ```bash
   flutter run
   ```

---

## Usage

**Students**
- Register appliances through the mobile app
- View per-appliance consumption charts and usage history
- Monitor the approval status of submitted devices

**Administrators**
- Review the incoming device validation queue
- Authorize or restrict appliances based on compliance rules
- Monitor aggregate and per-device power consumption across the hostel

---

## License

This project is licensed under the MIT License. See [LICENSE](LICENSE) for details.


