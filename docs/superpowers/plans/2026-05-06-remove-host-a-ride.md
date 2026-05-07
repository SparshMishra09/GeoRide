# Remove "Host a Ride" - Consolidate into "Create Ride & Confirm"

**Goal:** Remove duplicate "Host a Ride" flow (FAB + dialog) and ensure "Create Ride & Confirm" in AR overlay has working chat.

**Architecture:** Single unified ride creation flow via AR overlay. No more separate "Host a Ride" dialog.

**Tech Stack:** Flutter, Firebase Firestore, MapLibre GL

---

## Task 1: Remove "Host a Ride" FAB from home_screen.dart

**Files:**
- Modify: lib/screens/home_screen.dart:2420-2441

- [ ] **Step 1: Remove the "Host a Ride" FAB block**

Change (lines 2420-2441):
`dart
                  if (_myCurrentRide == null) ...[
                    // AR Navigation Mode FAB
                    _buildFab(
                      heroTag: 'ar_nav_mode',
                      icon: Icons.near_me,
                      tooltip: 'Start Journey',
                      onPressed: () => setState(() => _isArNavMode = true),
                      color: AppColors.accent1,
                      mini: false,
                    ),
                    const SizedBox(height: 12),
                    // Host Ride FAB  REMOVE THIS BLOCK
                    _buildFab(
                      heroTag: 'host_ride',
                      icon: Icons.add_circle,
                      tooltip: 'Host a Ride',
                      onPressed: _showHostRideDialog,
                      color: AppColors.cta,
                      mini: false,
                    ),
                    const SizedBox(height: 12),
                  ],
`

To:
`dart
                  if (_myCurrentRide == null) ...[
                    // AR Navigation Mode FAB (serves as unified Create Ride flow)
                    _buildFab(
                      heroTag: 'ar_nav_mode',
                      icon: Icons.near_me,
                      tooltip: 'Start Journey',
                      onPressed: () => setState(() => _isArNavMode = true),
                      color: AppColors.accent1,
                      mini: false,
                    ),
                    const SizedBox(height: 12),
                  ],
`

- [ ] **Step 2: Commit**

---

## Task 2: Remove _showHostRideDialog method

**Files:**
- Modify: lib/screens/home_screen.dart:1690-1750

- [ ] **Step 1: Remove the entire _showHostRideDialog method**

Delete lines 1690-1750.

- [ ] **Step 2: Commit**

---

## Task 3: Remove _HostRideDialog class

**Files:**
- Modify: lib/screens/home_screen.dart:2615-2797

- [ ] **Step 1: Remove _HostRideDialog StatefulWidget (lines 2615-2622)**
- [ ] **Step 2: Remove _HostRideDialogState class (lines 2624-2797)**
- [ ] **Step 3: Verify build - flutter analyze lib/screens/home_screen.dart**
- [ ] **Step 4: Commit**

---

## Task 4: Fix broken _buildChatButton in ArNavigationOverlay

**Files:**
- Modify: lib/widgets/ar_navigation_overlay.dart:1417-1423

Current (broken - onPressed is empty):
`dart
  Widget _buildChatButton() {
    return FloatingActionButton(
      onPressed: () {},
      backgroundColor: Colors.cyanAccent,
      child: const Icon(Icons.chat_bubble, color: Colors.black),
    );
  }
`

Fix - add actual chat modal:
`dart
  Widget _buildChatButton() {
    return FloatingActionButton(
      onPressed: () {
        if (_currentRouteId != null) {
          showModalBottomSheet(
            context: context,
            backgroundColor: Colors.transparent,
            isScrollControlled: true,
            builder: (ctx) => _ArRideChatSheet(rideId: _currentRouteId!),
          );
        }
      },
      backgroundColor: Colors.cyanAccent,
      child: const Icon(Icons.chat_bubble, color: Colors.black),
    );
  }
`

- [ ] **Step 1: Copy _ChatModalSheet from home_screen.dart into ar_navigation_overlay.dart as _ArRideChatSheet**
- [ ] **Step 2: Update _buildChatButton to use _ArRideChatSheet**
- [ ] **Step 3: Verify build - flutter analyze lib/widgets/ar_navigation_overlay.dart**
- [ ] **Step 4: Commit**

---

## Task 5: Verify full workflow

- [ ] **Step 1: Run app - verify single unified flow**
- [ ] **Step 2: No duplicate "Host a Ride" elements remain**

---

## File Summary

| File | Change |
|------|--------|
| lib/screens/home_screen.dart | Remove Host Ride FAB, _showHostRideDialog, _HostRideDialog class |
| lib/widgets/ar_navigation_overlay.dart | Add _ArRideChatSheet, fix _buildChatButton onPressed |
