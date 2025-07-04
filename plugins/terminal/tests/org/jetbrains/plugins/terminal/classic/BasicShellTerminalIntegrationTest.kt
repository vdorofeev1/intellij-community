// Copyright 2000-2020 JetBrains s.r.o. Use of this source code is governed by the Apache 2.0 license that can be found in the LICENSE file.
package org.jetbrains.plugins.terminal.classic

import com.intellij.execution.CommandLineUtil
import com.intellij.openapi.util.SystemInfo
import com.intellij.testFramework.fixtures.BasePlatformTestCase
import com.intellij.util.io.delete
import org.jetbrains.plugins.terminal.JBTerminalSystemSettingsProvider
import org.jetbrains.plugins.terminal.ShellTerminalWidget
import org.jetbrains.plugins.terminal.classic.fixture.TestShellSession
import org.jetbrains.plugins.terminal.classic.fixture.TestTerminalBufferWatcher
import org.junit.Assume
import java.nio.charset.StandardCharsets
import java.nio.file.Files

class BasicShellTerminalIntegrationTest : BasePlatformTestCase() {
  fun testEchoAndClear() {
    val session = TestShellSession(project, testRootDisposable)
    val command = if (SystemInfo.isWindows) {
      $$"$env:_MY_FOO = 'test'; echo \"1`n2`n$env:_MY_FOO\""
    }
    else {
      $$"_MY_FOO=test; echo -e \"1\\n2\\n$_MY_FOO\""
    }
    session.executeCommand(command)
    session.awaitScreenLinesEndWith(listOf("1", "2", "test"), 10000)
    session.executeCommand("clear")
    session.awaitScreenLinesAre(emptyList(), 10000)
  }

  fun testCommandsExecuteInOrder() {
    Assume.assumeFalse(SystemInfo.isWindows)
    val outputFile = Files.createTempFile("output", ".txt")
    val widget = ShellTerminalWidget(project, JBTerminalSystemSettingsProvider(), testRootDisposable)
    val commandCount = 10
    for (i in 1..commandCount) {
      if (SystemInfo.isWindows) {
        // PowerShell 5.1 has UTF-16LE output encoding by default
        widget.executeCommand("Add-Content -Path '$outputFile' -Value $i -Encoding ASCII")
      }
      else {
        widget.executeCommand("echo " + i + " >> " + CommandLineUtil.posixQuote(outputFile.toString()))
      }
    }
    TestShellSession.start(widget)
    val finishMarker = "All commands have been executed"
    widget.executeWithTtyConnector {
      widget.executeCommand("echo " + CommandLineUtil.posixQuote(finishMarker))
    }
    val watcher = TestTerminalBufferWatcher(widget.terminalTextBuffer, widget.terminal)
    watcher.awaitScreenLinesEndWith(listOf(finishMarker), 60_000)
    val actualOutputLines = Files.readAllLines(outputFile, StandardCharsets.US_ASCII)

    outputFile.delete()
    val expectedOutputLines: List<String> = (1..commandCount).map { it.toString() }
    assertEquals(expectedOutputLines, actualOutputLines)
  }
}
