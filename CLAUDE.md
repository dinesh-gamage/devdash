# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

DevDash is a native macOS application built with SwiftUI for managing local development workflows. It provides:
1. **Service Management** - Start/stop local development services, view logs, track errors/warnings, handle port conflicts
2. **EC2 Management** - Fetch/cache public IPs, restart instances, health checks, SSH terminals and SSH tunnels
3. **Credentials Management** - Secure credential storage with Apple Keychain and biometric authentication
4. **AWS Vault Profiles** - Manage aws-vault profiles and cached credential sessions
5. **Resource Monitor** - System and DevDash CPU/memory/swap/network/disk metrics and top processes
6. **Storage Manager** - Scan for junk, caches, large/old and duplicate files, then move them to Trash
7. **Docker Manager** - Containers and images on two engines: Docker (Colima) and Apple Containers
8. **Virtual Machines** - Lima VMs and Apple container machines
9. **Route 53 Records** - Keep selected A records pointed at EC2 IPs
10. **Settings** - Encrypted per-module backup to S3 and restore
11. **Dashboard** - Home screen with count widgets and summary panels from each module

## Development Rules

**These rules override all other considerations:**

1. **Performance First** - This app must remain lightweight with zero performance impact. Prevent memory leaks, ensure proper garbage collection, and clean up all resources (processes, tasks, observers). Profile memory usage for any significant changes.

2. **No Guessing, No Patronizing** - If you don't know or are unsure about implementation details, say so explicitly. Do not make assumptions. Ask clarifying questions before proceeding.

3. **Keep it DRY** - Eliminate code duplication. Extract shared logic to Core utilities. Reuse existing components before creating new ones.

4. **User-Friendly & Intuitive** - Design simple, clear interfaces. Provide immediate visual feedback. Make actions reversible where possible. Minimize cognitive load.

5. **Event-Driven Architecture** - Follow the established event-driven pattern (detailed below). NEVER use manual refresh triggers or polling. Let SwiftUI's reactive system handle updates automatically.

## Architecture

### Modular System
The app uses a **module-based architecture** where each feature is an independent, self-contained module:

**Module Protocol** (`Core/Models/Module.swift`):
- **DevDashModule**: Protocol defining module interface (id, name, icon, description, accentColor, sidebar/detail views)
  - Backup support: `backupFileName` and `exportForBackup() async throws -> Data` (full data, including secrets)
- **ModuleRegistry**: Singleton managing module registration and lookup
- Modules are registered in `DevDashApp.registerModules()`. Each module's `toastQueue` is attached in `ContentView`.
- `BiometricAuthManager` gates the whole window via `AuthenticationGateView`.

**Current Modules** (id in brackets):
- **ServiceManagerModule** (`service-manager`) - Service lifecycle management
- **EC2ManagerModule** (`ec2-manager`) - EC2 IPs, restart, health, SSH, tunnels
- **CredentialsManagerModule** (`credentials-manager`) - Secure credential storage
- **AWSVaultManagerModule** (`aws-vault-manager`) - aws-vault profiles
- **ResourceMonitorModule** (`resource-monitor`) - System/DevDash metrics
- **StorageManagerModule** (`storage-manager`) - Disk cleanup
- **DockerManagerModule** (`docker-manager`) - Colima / Apple Containers, containers, images
- **VMManagerModule** (`vm-manager`) - Lima VMs and Apple container machines
- **Route53ManagerModule** (`route53-manager`) - Selected Route 53 A records
- **SettingsModule** (`settings`) - Backup/restore; shown at the bottom of the sidebar, not in the module list

### Directory Structure
```
DevDash/
├── Core/                     # Shared infrastructure
│   ├── Models/              # Module protocol, registry, backup config/status
│   ├── Components/          # Reusable UI (buttons, forms, logs, etc.)
│   ├── Theme/              # AppTheme, typography, colors
│   ├── Utilities/          # Helpers (LogParser, StorageManager, BackupManager, etc.)
│   └── Protocols/          # Shared interfaces (OutputViewDataSource)
├── Modules/                 # Feature modules
│   ├── ServiceManager/
│   ├── EC2Manager/
│   ├── CredentialsManager/
│   ├── AWSVaultManager/
│   ├── ResourceMonitor/
│   ├── StorageManager/
│   └── DockerManager/
├── Settings/                # Settings module, backup views, storage scan settings view
├── Views/Dashboard/         # Home dashboard + 12-column grid
├── ContentView.swift        # Root navigation (module list ↔ module sidebar, dashboard when none selected)
└── DevDashApp.swift        # App entry + module registration
```

### Service Manager Module

Key components in `Modules/ServiceManager/`:

**ServiceManagerModule.swift**:
- **ServiceManagerState**: Singleton @ObservableObject managing module state, alerts, selected service
- **ServiceManagerSidebarView**: Toolbar + service list with add/edit/delete/import/export
- **ServiceManagerDetailView**: Detail pane showing selected service or empty state

**Models/ServiceModels.swift**:
- **ServiceConfig**: Codable config model (name, command, workingDir, port, env vars)

**Runtime/ServiceRuntime.swift**:
- **ServiceRuntime**: ObservableObject managing process lifecycle, log streaming, error/warning parsing
- Runs services as `/bin/zsh` processes with Pipe-based stdout/stderr streaming
- Ring buffer for logs with proactive trimming at maxLogLines
- Real-time log parsing for errors/warnings with stack trace detection

**Managers/ServiceManager.swift**:
- **ServiceManager**: Data layer handling persistence (UserDefaults), import/export (JSON), CRUD operations
- Stores services in UserDefaults with key "services"

**Views/**:
- **ServiceDetailView**: Control panel with start/stop, logs, errors, warnings tabs
- **ServiceListItem**: Sidebar list item with status indicators
- **AddServiceView, EditServiceView**: Forms for service CRUD
- **JSONEditorView**: Direct JSON editing with validation

### EC2 Manager Module

Key components in `Modules/EC2Manager/`:

**EC2ManagerModule.swift**:
- **EC2ManagerState**: Singleton managing groups, selected group, instance CRUD operations
- **EC2ManagerSidebarView**: Toolbar + instance group list with add/edit/delete/import/export
- **EC2ManagerDetailView**: Detail pane for selected group

**Models/EC2Models.swift**:
- **EC2Instance**: Instance name, ID, cached IP, last fetch timestamp, fetch error, optional SSHConfig
- **InstanceGroup**: Regional grouping with AWS profile, region, instances, group SSHConfig, tunnels
- **SSHConfig / SSHTunnel**: SSH user/key/options; local port forward through a bastion instance

**Managers/InstanceGroupManager.swift**:
- Credentials come from `ProcessEnvironment.getEnvironment(withAWSProfile:region:)` (aws-vault session via `AWSVaultServerManager`)
- Runs `aws ec2 describe-instances` / stop / start / wait / describe-instance-status asynchronously (Task.detached)
- Opens SSH terminals (`TerminalLauncher`) and runs tunnels (`Runtime/TunnelRuntime.swift`)
- Stores groups in UserDefaults with key "instanceGroups" (no default groups)

**Views/**:
- **InstanceGroupDetailView**: Table showing instance name, ID, cached IP, last fetch time, fetch button
- **AddInstanceGroupView, EditInstanceGroupView**: Group CRUD forms
- **AddInstanceView, EditInstanceView**: Instance CRUD forms
- **InstanceGroupJSONEditorView**: Direct JSON editing

### Credentials Manager Module

Key components in `Modules/CredentialsManager/`:

**CredentialsManagerModule.swift**:
- **CredentialsManagerState**: Singleton managing credentials, auth state, revealed passwords/fields
- **CredentialsManagerSidebarView**: Category filter, search bar, credential list
- **CredentialsManagerDetailView**: Detail pane for selected credential

**Models/CredentialModels.swift**:
- **Credential**: Title, category, username, password (Keychain key), custom fields, notes
- **CredentialField**: Custom field with key, value, isSecret flag
- **CredentialCategory**: Predefined categories (Databases, API Keys, SSH, etc.)

**Managers/CredentialsManager.swift**:
- Manages credential CRUD operations
- Coordinates between UserDefaults (metadata) and Keychain (secrets)
- Import/Export functionality (metadata only, no passwords)
- Search and filter logic

**Views/**:
- **CredentialDetailView**: Shows credential with reveal/hide toggles and copy buttons
- **AddCredentialView**: Form for creating new credentials with password confirmation
- **EditCredentialView**: Form for editing credentials with optional password update
- **CredentialListItem**: Sidebar item with category icon and metadata

### Route 53 Records Module (`Modules/Route53Manager/`)
- Keeps hand-picked A records (e.g. `*.v5.lucyday.io`) pointed at the right IP. Never lists or touches other records in a zone.
- **HostedZone** (name, zone ID, aws-vault profile) holds **DNSRecord**s. A record can link to an EC2 Manager instance (`InstanceLink`).
- Update flow: validate IPv4, then read the live record (`list-resource-record-sets`), then confirm old → new, then UPSERT keeping the live TTL.
  - Refuses to create missing records and does not support alias records.
- "Update from EC2" calls `InstanceGroupManager.refreshPublicIP`, which also refreshes the EC2 module's cached IP.
- UserDefaults keys "route53Zones" and "route53ChangeLog" (newest 500 entries). The backup file is `route53.json`.
- Import/export covers zones and records only. Import matches zones by zone ID and records by name. It adds and updates, never deletes.

### AWS Vault Manager Module (`Modules/AWSVaultManager/`)
- **AWSVaultManager**: profile metadata in UserDefaults key "awsVaultProfiles", aws-vault CLI integration, Keychain health check
- **AWSVaultServerManager** (`Core/Utilities/`): caches `aws-vault exec --json` sessions per profile until expiry; cleared on app quit

### Resource Monitor Module (`Modules/ResourceMonitor/`)
- **SystemMetricsMonitor**: reads CPU, memory, swap, network, disk via system APIs on a 1s timer
  - This timer is the one allowed polling exception. It only publishes when values change (`shouldPublish`).
- Two views: **Overall** (system) and **DevDash** (the app's own processes). Dashboard widgets reuse them.

### Storage Manager Module (`Modules/StorageManager/`)
- **CleanupManager**: priority-ordered scan with path dedup (system caches, junk, developer tools, trash, downloads, user folders, large/old files, duplicates via MD5)
- **SafetyDatabase** (actor): allow-list of scan/clean targets and protected paths. All deletes must pass it.
- **DirectorySizeCalculator** (actor), **FullDiskAccessManager**
- **StorageScanSettingsManager**: enabled categories, scan locations, ignore patterns, deletion mode
- SAFETY: `cleanSelected()` always moves to Trash. Permanent delete is disabled on purpose until validated.

### Docker Manager Module (`Modules/DockerManager/`)
- Two engines (`ContainerEngine`): `.docker` (Colima, `docker` CLI) and `.apple` (`container` CLI). `ContainerConfig.engine` nil means docker.
- Sidebar: Apple Containers first, then Colima. Each engine host (start/stop via `EngineRuntime`), then its Containers and Images.
- Colima: the host page creates, edits (CPUs, memory, disk) and deletes the default instance. Status comes from `colima list --json` (`ColimaInstance`).
- **DockerManager**: container configs in UserDefaults key "containers"; `ContainerRuntime` per container; images per engine.
- **ContainerScanner**: finds containers created outside DevDash and maps them to `ContainerConfig` (drops env vars that match the image defaults). "Add" adopts them without recreating.
- Delete offers "Remove from DevDash" (keeps the container) or "Delete Container" (also deletes it in the engine).
- Apple's CLI has no restart policy.

### Virtual Machines Module (`Modules/VMManager/`)
- Reads VMs live from `limactl list --json` and `container machine list --format json`. Stores nothing.
- Start, stop, delete, and open a shell in Terminal (`TerminalLauncher.open(command:)`).
- Backup `vms.json` holds each Lima VM's `lima.yaml`.

### Settings Module & Backup (`Settings/`, `Core/Utilities/BackupManager.swift`)
- Backs up each module's `exportForBackup()` data, encrypted with `FileEncryption` (AES-256-GCM, PBKDF2 key from a passphrase in Keychain)
- Uploads with `aws-vault exec {profile} -- aws s3 cp` to the configured bucket/path; restore downloads and decrypts
- Config in UserDefaults key "backupConfig", last status in "lastBackupStatus"
- New modules MUST implement `backupFileName` and `exportForBackup()`

### Dashboard (`Views/Dashboard/`)
- `DashboardView` shows when no module is selected. It uses a 12-column `DashboardGrid`.
- Row 1: count widgets. Row 2: Service, EC2 and Resource Monitor panels. Tapping one opens its module.

### Event-Driven Architecture & State Management

**CRITICAL: This pattern must be followed for all modules to prevent performance issues.**

#### The Problem We Solved

Initial implementation had severe performance issues:
- **100% CPU usage** from infinite rendering loops
- **Constant re-renders** when observing objects with frequently updating properties (logs updating 10x/second)
- **UI not updating** when nested ObservableObject changes occurred
- **Manual refresh hacks** using `listRefreshTrigger = UUID()` and `objectWillChange.send()`

#### The Solution: Lightweight State Pattern with Event Forwarding

All modules now follow this architecture:

```
┌─────────────────────────────────────────────────────────┐
│ ModuleState (ObservableObject)                          │
│ - Singleton, holds UI state                             │
│ - Forwards manager.objectWillChange to self             │
│ - Views observe this                                     │
└──────────────────┬──────────────────────────────────────┘
                   │
                   ▼
┌─────────────────────────────────────────────────────────┐
│ Manager (ObservableObject)                              │
│ - Publishes LIGHTWEIGHT list (ServiceInfo, not Runtime) │
│ - Handles CRUD, persistence, import/export              │
│ - Private full objects (with logs, processes, etc.)     │
│ - Public lightweight snapshots for UI                   │
└──────────────────┬──────────────────────────────────────┘
                   │
                   ▼
┌─────────────────────────────────────────────────────────┐
│ Runtime/Heavy Objects (ObservableObject)                │
│ - Logs, processes, frequently updating data             │
│ - NOT exposed to list views                             │
│ - Fetched on-demand via manager.getRuntime(id)          │
│ - Only detail views observe these                       │
└─────────────────────────────────────────────────────────┘
```

#### Mandatory Rules

**DO:**

1. **Use Combine forwarding for nested ObservableObjects**:
   ```swift
   @MainActor
   class ModuleState: ObservableObject {
       @Published var manager: Manager
       private var cancellables = Set<AnyCancellable>()

       private init() {
           self.manager = Manager(...)

           // REQUIRED: Forward manager changes to state
           manager.objectWillChange.sink { [weak self] _ in
               self?.objectWillChange.send()
           }
           .store(in: &cancellables)
       }
   }
   ```

2. **Separate lightweight state from heavy runtime data**:
   ```swift
   // Lightweight - safe for list views
   struct ServiceInfo: Identifiable {
       let id: UUID
       let name: String
       let isRunning: Bool
       let port: Int?
       // NO logs, NO processes, NO frequently updating data
   }

   // Manager exposes lightweight list
   @MainActor
   class Manager: ObservableObject {
       @Published var servicesList: [ServiceInfo] = []
       private var runtimes: [UUID: ServiceRuntime] = [:]

       func getRuntime(id: UUID) -> ServiceRuntime? {
           return runtimes[id]
       }
   }
   ```

3. **Subscribe to runtime changes to auto-refresh list**:
   ```swift
   private func subscribeToRuntime(_ runtime: ServiceRuntime) {
       runtime.objectWillChange.sink { [weak self] _ in
           self?.refreshServicesList()
       }
       .store(in: &cancellables)
   }

   func refreshServicesList() {
       servicesList = runtimes.values.map { runtime in
           ServiceInfo(/* map only lightweight properties */)
       }
   }
   ```

4. **Let @Published trigger updates automatically** - Never manually call `objectWillChange.send()` in CRUD methods

5. **Use on-demand fetching for heavy data**:
   ```swift
   // In detail view
   if let runtime = manager.getRuntime(id: serviceInfo.id) {
       runtime.start()
   }
   ```

**DO NOT:**

1. ❌ **NEVER observe objects with frequently updating @Published properties in list views**:
   ```swift
   // WRONG - logs update 10x/second, causes constant re-renders
   struct ServiceRow: View {
       @ObservedObject var service: ServiceRuntime
   }

   // CORRECT - lightweight, stable data
   struct ServiceRow: View {
       let serviceInfo: ServiceInfo
       let manager: ServiceManager
   }
   ```

2. ❌ **NEVER use manual refresh triggers**:
   ```swift
   // WRONG
   @Published var listRefreshTrigger = UUID()

   func addItem() {
       items.append(newItem)
       listRefreshTrigger = UUID()  // ❌ Never do this
       objectWillChange.send()      // ❌ Never do this
   }

   // CORRECT
   func addItem() {
       items.append(newItem)  // ✓ @Published triggers update
   }
   ```

3. ❌ **NEVER create computed properties that recreate publishers**:
   ```swift
   // WRONG - infinite loop!
   var servicesPublisher: AnyPublisher<Void, Never> {
       manager.objectWillChange.eraseToAnyPublisher()
   }

   // CORRECT - use @ObservedObject
   @ObservedObject var manager: ServiceManager
   ```

4. ❌ **NEVER pass full runtime objects to list item views**:
   ```swift
   // WRONG
   ForEach(manager.services) { service in  // ❌ Full runtime
       ServiceRow(service: service)
   }

   // CORRECT
   ForEach(manager.servicesList) { serviceInfo in  // ✓ Lightweight
       ServiceRow(serviceInfo: serviceInfo, manager: manager)
   }
   ```

5. ❌ **NEVER forget to store Combine subscriptions**:
   ```swift
   // WRONG - subscription will be deallocated
   manager.objectWillChange.sink { _ in
       self?.objectWillChange.send()
   }

   // CORRECT
   manager.objectWillChange.sink { _ in
       self?.objectWillChange.send()
   }
   .store(in: &cancellables)  // ✓ Must store
   ```

#### Example: ServiceManager Architecture

**ServiceInfo (Lightweight)**:
```swift
struct ServiceInfo: Identifiable, Equatable, Hashable {
    let id: UUID
    let name: String
    let isRunning: Bool
    let isExternallyManaged: Bool
    let hasPortConflict: Bool
    let processingAction: ServiceAction?
    let port: Int?
    let workingDirectory: String
    let command: String
}
```

**ServiceManager (Manager)**:
```swift
@MainActor
class ServiceManager: ObservableObject {
    @Published var servicesList: [ServiceInfo] = []  // Lightweight, public
    private var runtimes: [UUID: ServiceRuntime] = [:]  // Heavy, private
    private var cancellables = Set<AnyCancellable>()

    func getRuntime(id: UUID) -> ServiceRuntime?

    private func subscribeToRuntime(_ runtime: ServiceRuntime) {
        runtime.objectWillChange.sink { [weak self] _ in
            self?.refreshServicesList()
        }.store(in: &cancellables)
    }

    func refreshServicesList() {
        servicesList = runtimes.values.map { ServiceInfo(...) }
    }
}
```

**ServiceRuntime (Heavy Runtime)**:
```swift
@MainActor
class ServiceRuntime: ObservableObject {
    @Published var logs: String = ""  // Updates 10x/second
    @Published var isRunning: Bool = false
    // ... process, pipes, etc.
}
```

**ServiceManagerState (Module State)**:
```swift
@MainActor
class ServiceManagerState: ObservableObject {
    static let shared = ServiceManagerState()
    @Published var manager: ServiceManager
    private var cancellables = Set<AnyCancellable>()

    private init() {
        self.manager = ServiceManager(...)

        // Forward manager changes to state
        manager.objectWillChange.sink { [weak self] _ in
            self?.objectWillChange.send()
        }.store(in: &cancellables)
    }
}
```

**Views**:
```swift
// List view - observes lightweight state
struct ServiceListItem: View {
    let serviceInfo: ServiceInfo  // Lightweight
    let manager: ServiceManager

    var body: some View {
        HStack {
            Text(serviceInfo.name)
            if serviceInfo.isRunning {
                Circle().fill(.green)
            }
        }
        .onTapGesture {
            // Fetch heavy data on-demand
            manager.getRuntime(id: serviceInfo.id)?.start()
        }
    }
}

// Detail view - can observe heavy runtime
struct ServiceDetailView: View {
    @ObservedObject var service: ServiceRuntime  // OK here

    var body: some View {
        ScrollView {
            Text(service.logs)  // Frequent updates OK in detail view
        }
    }
}
```

#### Performance Testing

Before committing any state management changes:

1. **Check CPU usage** with Activity Monitor or `htop`
2. **Test import/CRUD operations** - UI must update immediately
3. **Test with running services** - CPU should remain low
4. **Profile memory** - No leaks after operations

### Core Infrastructure

**Shell commands** (all modules):
- Run via `Process` with `/bin/zsh -c` (or `-l -c`) on a background task, never on the main thread
- Environment comes from `ProcessEnvironment.shared.getEnvironment(...)`. Use `withAWSProfile:region:` for AWS calls.
- For new code, prefer `ShellCommand.run(tool, args, env:)` (`Core/Utilities/ShellCommand.swift`). It takes an argument array with no shell, so user input can't inject commands.

**Process Management** (ServiceRuntime):
- Services run as `/bin/zsh` processes
- Streams stdout/stderr via Pipe with live readability handler
- Ring buffer storage with fixed size and proactive trimming
- Pattern-based error/warning detection
- Automatic stack trace collection after errors
- Port conflict detection via `lsof`
- Process termination and restart capabilities

**Reusable UI Components** (`Core/Components/`):
- **VariantComponents**: Buttons with primary/danger/ghost variants
- **FormComponents**: Form fields, labels, text editors
- **ServiceOutputPanel**: Log viewer with search and error/warning tabs
- **LogView**: Virtualized log rendering with syntax highlighting
- **CopyableField**: One-click copy text fields
- **RelativeTimeText**: Auto-updating relative timestamps
- **ErrorWarningListView**: Shared error/warning list display
- **ModuleDetailHeader**: Standard header for module detail views
- **ModuleSidebarList**: Reusable sidebar list with toolbar
- **CommandOutputView / OutputSlideOver**: Show a command's output log (`CommandOutputViewModel`)
- **DashboardCard, StatCard**: Dashboard widget building blocks
- **AuthenticationGateView**: Biometric lock screen
- **PlainTextEditor**: NSTextView wrapper without smart quotes

**Utilities** (`Core/Utilities/`):
- **LogParser**: Real-time error/warning detection with pattern matching
  - Error patterns: "error", "fail", "exception", "panic", "traceback", etc.
  - Warning patterns: "warning", "deprecated", "caution", etc.
  - Automatic stack trace collection after errors
- **ProcessEnvironment**: Shell environment variable resolution
- **StorageManager**: UserDefaults persistence layer with Codable support
- **ImportExportManager**: JSON import/export with file panels (NSSavePanel/NSOpenPanel)
- **AlertQueue**: Sequential alert presentation to prevent overlapping dialogs
- **KeychainManager**: Secure storage wrapper for Apple Keychain Services API
  - Save/retrieve/delete operations
  - Support for String and Data types
  - Error handling with KeychainError enum
- **BiometricAuthManager**: LocalAuthentication integration
  - Touch ID/Face ID/Password authentication
  - Session-based authentication caching
  - Session invalidation on app background/terminate
- **AWSVaultServerManager**: Cached aws-vault credential sessions per profile
- **ToastQueue**: Sequential toast messages (one per module state, attached in `ContentView`)
- **BackupManager / FileEncryption**: Encrypted S3 backup and restore
- **TerminalLauncher**: Opens commands (e.g. SSH) in Terminal

**Theme System** (`Core/Theme/AppTheme.swift`):
- Centralized typography (h1, h2, h3, body, caption)
- Color palette with gradient support
- Responsive accent color switching per module

**Performance Optimizations**:
- Debounced search (300ms delay)
- Lazy virtualized log rendering
- Ring buffer storage for logs (fixed size, automatic trimming)
- Async operations for shell commands and AWS CLI calls
- Proper resource cleanup (processes, tasks, observers)

## Development Commands

This is a standard Xcode project. No build scripts, tests, or linters are configured.

**Build & Run:**
Open `DevDash.xcodeproj` in Xcode and use Cmd+R to build and run.
Command line build: `xcodebuild -project DevDash.xcodeproj -scheme DevDash build`

**Platform:**
macOS only (uses AppKit for file panels)

**Requirements:**
- macOS 26.2+ (deployment target in the project)
- aws-vault installed and configured with profiles
- AWS CLI v2 installed
- Docker CLI + Colima (Docker Manager only)
- Full Disk Access (Storage Manager only, for a complete scan)

## Data Storage

**Services:**
- Persisted to `UserDefaults` with key "services" as JSON-encoded array of `ServiceConfig`
- Import/Export uses JSON format via `NSSavePanel`/`NSOpenPanel`

**EC2 Instance Groups:**
- Persisted to `UserDefaults` with key "instanceGroups" as JSON-encoded array of `InstanceGroup`

**Other UserDefaults keys** (all via `StorageManager.shared`, JSON-encoded arrays):
- "awsVaultProfiles", "containers", "backupConfig", "lastBackupStatus"
- Credentials metadata in UserDefaults. Passwords and secret fields in Keychain.
- Storage scan settings via `StorageScanSettingsManager`

## Key Behaviors

**Services:**
- Services can only run if ports are free (checked via `lsof`)
- Log parsing happens in real-time as output arrives
- Search in logs highlights matches with yellow background
- Auto-scroll disabled when searching logs
- Import replaces services with matching names, adds new ones

**EC2 Instances:**
- IP fetches run asynchronously (no UI blocking)
- Last known IP and fetch timestamp cached locally
- Manual fetch only (no auto-refresh)
- aws-vault prompts for credentials if session expired
