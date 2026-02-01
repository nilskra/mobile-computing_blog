# 📱 Mobile Computing – Flutter Blog App

## Architekturübersicht

Das Projekt basiert auf einer **Offline-First Architektur** mit klarer Trennung von UI, Business-Logik und Datenzugriff. Ziel ist eine robuste, testbare und erweiterbare Flutter-App, die auch ohne Internetverbindung voll funktionsfähig bleibt.

### Schichten

```
lib/
├─ core/          → Basisbausteine (Result, Exceptions, Logger)
├─ data/
│  ├─ api/        → REST-Kommunikation (BlogApi)
│  ├─ repository/ → Zentrale Logik (BlogRepository)
│  └─ sync/       → Offline-Synchronisation
├─ domain/
│  └─ models/     → Zentrale Datenmodelle (Blog)
├─ local/
│  ├─ cache/      → Lokaler Cache (Blogs)
│  └─ pending/    → Pending Operations (Offline Queue)
├─ presentation/
│  ├─ screens/    → UI Screens
│  └─ viewmodels/ → State & Business-Logik (MVVM)
└─ main.dart
```

---

## Datenfluss (Offline-First)

1. **UI → ViewModel**
2. **ViewModel → BlogRepository**
3. **Repository entscheidet:**

   * **Online:** API Call → Cache aktualisieren
   * **Offline:** Optimistisches Update + Pending Operation speichern
4. **SyncService:**

   * Führt gespeicherte Pending Operations aus, sobald wieder eine Internetverbindung besteht

Unterstützte Offline-Operationen:

* Erstellen eines Blogposts
* Aktualisieren eines Blogposts
* Löschen eines Blogposts
* Like / Unlike eines Blogposts

---

## Architektur- & Designentscheidungen

* **MVVM Pattern**

  * Screens enthalten nur UI-Code
  * ViewModels kapseln State und Logik

* **Repository Pattern**

  * Ein zentraler Einstiegspunkt für alle Datenzugriffe

* **Optimistic UI Updates**

  * UI reagiert sofort, auch im Offline-Modus

* **Dependency Injection**

  * Umsetzung mit `get_it` und `injectable`

---

## Technisches Setup

### Wichtige Libraries

* Flutter
* `http` – REST-Kommunikation
* `get_it` / `injectable` – Dependency Injection
* `uuid` – Identifikation von Pending Operations
* Lokaler Cache & Pending Queue

---

## Entwicklungsmodus auf Android

### Voraussetzungen

* Flutter SDK installiert
* Android Studio oder Android SDK
* Android Emulator **oder** physisches Android-Gerät
* USB-Debugging aktiviert (bei physischem Gerät)

---

### Projekt starten

1. **Abhängigkeiten installieren**

   ```bash
   flutter pub get
   ```

2. **Code-Generierung (Dependency Injection)**

   ```bash
   flutter pub run build_runner build --delete-conflicting-outputs
   ```

3. **Verfügbare Geräte prüfen**

   ```bash
   flutter devices
   ```

4. **App starten**

   ```bash
   flutter run
   ```

---

## Besonderes Setup (Android)

* Das Backend wird **remote** betrieben
* Kein lokaler Server notwendig
* Die App ist auch **ohne Internetverbindung** nutzbar

Falls das Backend **HTTP (kein HTTPS)** verwendet, muss folgendes im `AndroidManifest.xml` gesetzt sein:

```xml
android:usesCleartextTraffic="true"
```

---

## Logging & Debugging

Zur besseren Nachvollziehbarkeit sind strukturierte Logs integriert:

* `[REPO]` – Repository-Entscheidungen
* `[PENDING]` – Offline gespeicherte Aktionen
* `[SYNC]` – Synchronisationsprozesse

Diese Logs helfen insbesondere beim Debuggen von Offline- und Sync-Problemen.

---

