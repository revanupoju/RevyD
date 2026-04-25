import AppKit

extension RevyCharacter {

    func horizontalRangeMetrics(screen: NSScreen, dockX: CGFloat, dockWidth: CGFloat) -> (minX: CGFloat, travelDistance: CGFloat) {
        if usesExpandedHorizontalRange {
            let margin: CGFloat = 24
            let minX = screen.visibleFrame.minX + margin
            let availableWidth = screen.visibleFrame.width - margin * 2
            return (minX, max(availableWidth - displayWidth, 0))
        }
        let desiredInset = min(18.0, max(10.0, dockWidth * 0.025))
        let minimumVisibleTravel: CGFloat = 28.0
        let maximumInset = max((dockWidth - displayWidth - minimumVisibleTravel) / 2.0, 0)
        let edgeInset = min(desiredInset, maximumInset)
        let minX = dockX + edgeInset
        let availableWidth = max(dockWidth - edgeInset * 2.0, 0)
        return (minX, max(availableWidth - displayWidth, 0))
    }

    func beginHorizontalDrag(at event: NSEvent) {
        isDraggingHorizontally = true
        usesExpandedHorizontalRange = true
        isWalking = false
        isPaused = true
        pauseEndTime = CACurrentMediaTime() + 8.0
        setFacing(.front)
        continueHorizontalDrag(with: event)
    }

    func continueHorizontalDrag(with event: NSEvent) {
        guard isDraggingHorizontally,
              let controller,
              let metrics = controller.currentDockMetrics()
        else { return }

        let pointerLocation = NSEvent.mouseLocation
        let horizontalMetrics = horizontalRangeMetrics(
            screen: metrics.screen,
            dockX: metrics.dockX,
            dockWidth: metrics.dockWidth
        )
        let visualX = pointerLocation.x - displayWidth / 2
        let rawProgress = horizontalMetrics.travelDistance > 0
            ? (visualX - horizontalMetrics.minX) / horizontalMetrics.travelDistance
            : 0
        positionProgress = min(max(rawProgress, 0), 1)

        let bottomPadding = displayHeight * 0.15
        let y = metrics.dockTopY - bottomPadding + yOffset
        window.setFrameOrigin(NSPoint(
            x: horizontalMetrics.minX + horizontalMetrics.travelDistance * positionProgress,
            y: y
        ))
        updatePopoverPosition()
        updateThinkingBubble()
    }

    func endHorizontalDrag() {
        isDraggingHorizontally = false
        pauseEndTime = CACurrentMediaTime() + Double.random(in: 4.0...8.0)
    }

    func startWalk() {
        isPaused = false
        isWalking = true
        walkStartTime = CACurrentMediaTime()

        if positionProgress > 0.85 {
            goingRight = false
        } else if positionProgress < 0.15 {
            goingRight = true
        } else {
            goingRight = Bool.random()
        }

        walkStartPos = positionProgress
        let referenceWidth: CGFloat = 500.0
        let walkPixels = CGFloat.random(in: walkAmountRange) * referenceWidth
        let walkAmount = currentTravelDistance > 0 ? walkPixels / currentTravelDistance : 0.3
        if goingRight {
            walkEndPos = min(walkStartPos + walkAmount, 1.0)
        } else {
            walkEndPos = max(walkStartPos - walkAmount, 0.0)
        }
        walkStartPixel = walkStartPos * currentTravelDistance
        walkEndPixel = walkEndPos * currentTravelDistance

        setFacing(goingRight ? .right : .left)
    }

    func enterPause() {
        isWalking = false
        isPaused = true
        setFacing(.front)
        let delay = Double.random(in: 3.0...6.0)
        pauseEndTime = CACurrentMediaTime() + delay
    }

    func movementPosition(at videoTime: CFTimeInterval) -> CGFloat {
        let dIn = fullSpeedStart - accelStart
        let dLin = decelStart - fullSpeedStart
        let dOut = walkStop - decelStart
        let v = 1.0 / (dIn / 2.0 + dLin + dOut / 2.0)

        if videoTime <= accelStart {
            return 0.0
        } else if videoTime <= fullSpeedStart {
            let t = videoTime - accelStart
            return CGFloat(v * t * t / (2.0 * dIn))
        } else if videoTime <= decelStart {
            let easeInDist = v * dIn / 2.0
            let t = videoTime - fullSpeedStart
            return CGFloat(easeInDist + v * t)
        } else if videoTime <= walkStop {
            let easeInDist = v * dIn / 2.0
            let linearDist = v * dLin
            let t = videoTime - decelStart
            return CGFloat(easeInDist + linearDist + v * (t - t * t / (2.0 * dOut)))
        } else {
            return 1.0
        }
    }

    func update(screen: NSScreen, dockX: CGFloat, dockWidth: CGFloat, dockTopY: CGFloat) {
        let horizontalMetrics = horizontalRangeMetrics(screen: screen, dockX: dockX, dockWidth: dockWidth)
        currentTravelDistance = horizontalMetrics.travelDistance

        let bottomPadding = displayHeight * 0.15
        let y = dockTopY - bottomPadding + yOffset

        // Dragging — just follow the pointer
        if isDraggingHorizontally {
            let x = horizontalMetrics.minX + currentTravelDistance * positionProgress
            window.setFrameOrigin(NSPoint(x: x, y: y))
            updatePopoverPosition()
            updateThinkingBubble()
            return
        }

        // Idle for popover — stay put
        if isIdleForPopover {
            let x = horizontalMetrics.minX + currentTravelDistance * positionProgress
            window.setFrameOrigin(NSPoint(x: x, y: y))
            updatePopoverPosition()
            updateThinkingBubble()
            return
        }

        let now = CACurrentMediaTime()

        // Paused — wait for pause to end, then start walking
        if isPaused {
            if now >= pauseEndTime {
                startWalk()
            } else {
                let x = horizontalMetrics.minX + currentTravelDistance * positionProgress
                window.setFrameOrigin(NSPoint(x: x, y: y))
                updateThinkingBubble()
                return
            }
        }

        // Walking — animate along the easing curve
        if isWalking {
            let elapsed = now - walkStartTime
            let videoTime = min(elapsed + accelStart, walkStop)
            let travelDistance = currentTravelDistance

            let walkNorm = videoTime >= walkStop ? 1.0 : movementPosition(at: videoTime)
            let currentPixel = walkStartPixel + (walkEndPixel - walkStartPixel) * walkNorm

            if travelDistance > 0 {
                positionProgress = min(max(currentPixel / travelDistance, 0), 1)
            }

            let x = horizontalMetrics.minX + travelDistance * positionProgress
            window.setFrameOrigin(NSPoint(x: x, y: y))

            if videoTime >= walkStop {
                positionProgress = walkEndPos
                window.setFrameOrigin(NSPoint(
                    x: horizontalMetrics.minX + travelDistance * positionProgress,
                    y: y
                ))
                enterPause()
                return
            }
        }

        updateThinkingBubble()
    }
}
