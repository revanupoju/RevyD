import AppKit

extension RevyCharacter {
    func wireSession(_ session: ClaudeSession) {
        session.onSessionReady = { [weak self] in
            self?.terminalView?.showWelcomePanel()
        }

        session.onSetupRequired = { [weak self] message in
            self?.setExpression(.alert)
            self?.terminalView?.endStreaming()
            self?.terminalView?.clearLiveStatus()
            self?.terminalView?.appendErrorBubble(message)
            self?.terminalView?.appendSystemBubble("To fix this:\n  1.  Install Claude Code from claude.ai/download\n  2.  Run `claude` in your terminal to log in\n  3.  Restart RevyD")
            DispatchQueue.main.asyncAfter(deadline: .now() + 5) { self?.setExpression(.idle) }
        }

        session.onTextDelta = { [weak self] delta in
            self?.setExpression(.thinking)
            self?.terminalView?.appendStreamingText(delta)
        }

        session.onText = { [weak self] text in
            self?.terminalView?.updateStreamingText(text)
        }

        session.onError = { [weak self] error in
            self?.setExpression(.alert)
            self?.terminalView?.endStreaming()
            self?.terminalView?.clearLiveStatus()
            self?.terminalView?.appendErrorBubble(error)
            // Reset expression after 3 seconds
            DispatchQueue.main.asyncAfter(deadline: .now() + 3) { self?.setExpression(.idle) }
        }

        session.onToolUse = { [weak self] title, summary in
            self?.setExpression(.thinking)
            self?.currentActivityStatus = summary
            self?.terminalView?.setLiveStatus(summary, isBusy: true)
        }

        session.onToolResult = { [weak self] text, isError in
            if isError {
                self?.terminalView?.setLiveStatus(text, isBusy: false, isError: true)
            }
        }

        session.onTurnComplete = { [weak self] in
            self?.setExpression(.happy)
            self?.terminalView?.endStreaming()
            self?.terminalView?.clearLiveStatus()
            self?.currentActivityStatus = ""
            self?.showBubble(text: "done", isCompletion: true)
            // Reset to idle after 4 seconds
            DispatchQueue.main.asyncAfter(deadline: .now() + 4) { self?.setExpression(.idle) }
        }
    }
}
