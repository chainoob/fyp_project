# SmartMeter: Future Work & Roadmap

This document outlines the planned features and improvements for the SmartMeter Energy Management System that were deferred to prioritize core system stability and production readiness.

## 1. AI Feedback Loop (Reinforcement Learning)
Currently, the backend has an endpoint (`/api/v1/feedback`) to process user corrections when the AI misidentifies an appliance state. 
- **Frontend Action**: Implement an interactive UI in the `AnalyticsScreen` allowing students to flag anomalies as "Correct" or "Incorrect".
- **Backend Action**: Enhance the reinforcement learning logic to not only adjust usage probabilities (`prob_day`/`prob_night`) but also to fine-tune the FHMM emission parameters (mean/variance) based on aggregated feedback across the user base.

## 2. Advanced Multi-State Disaggregation
While the system currently supports N-state models (distilled from REDD), the prediction mapping often defaults to evaluating the highest state.
- **Action**: Implement continuous state tracking in the Flutter app to show exactly *how* an appliance was used (e.g., distinguishing between a Fan on 'Low' vs. 'High' over a 24-hour period).

## 3. Real-Time Alerting (Push Notifications)
To transition the system from a passive dashboard to an active assistant.
- **Action**: Integrate **Firebase Cloud Messaging (FCM)**.
- **Triggers**:
  - Alert the student when a high-risk anomaly (e.g., an unregistered 2000W heater) is detected in their room.
  - Send "Daily Budget" summaries or warnings when a student is projected to exceed their monthly energy target.

## 4. Staff Productivity Dashboard
- **Action**: Create a `StaffRiskScreen` or enhance the `ManageBlock` screen for Facility Managers.
- **Features**:
  - A prioritized list of rooms with detected "Unregistered High-Load" appliances.
  - Automated report generation and CSV export capabilities for billing and compliance audits.

## 5. DevOps & Infrastructure Optimization
- **Caching**: Introduce a caching layer (e.g., Redis or Firestore TTL) for the `WeatherService` to minimize redundant calls to the OpenWeatherMap API and reduce latency.
- **CI/CD**: Set up GitHub Actions to automate testing and deployment to Google Cloud Run upon merging to the `main` branch.
- **Secrets Management**: Transition from environment variables to **Google Secret Manager** for injecting API keys and Firebase credentials securely into the Cloud Run instances.

## 6. Evolutionary Optimization Expansion
- **Action**: The current `EnergyOptimizer` (using SLSQP) works well for immediate adjustments. We can expand this using the included `deap` library to run a nightly Genetic Algorithm that optimizes campus-wide usage parameters based on historical 30-day billing cycles, providing more accurate benchmarks over time.
