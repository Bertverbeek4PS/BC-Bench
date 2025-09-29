import * as vscode from 'vscode';

export function activate(context: vscode.ExtensionContext) {
	console.log('Congratulations, your extension "bc-bench" is now active!');

	const startAutomationCommand = vscode.commands.registerCommand('bc-bench.startAutomation', async () => {
		try {
			await runAutomationSequence();
		} catch (error) {
			vscode.window.showErrorMessage(`Automation failed: ${error}`);
		}
	});

	context.subscriptions.push(startAutomationCommand);
}

async function runAutomationSequence(): Promise<void> {
	try {
		// Most important reference files:
		// 1. https://github.com/microsoft/vscode/blob/main/src/vs/workbench/contrib/chat/browser/actions/chatActions.ts
		// 2. https://github.com/microsoft/vscode/blob/main/extensions/vscode-api-tests/src/singlefolder-tests/chat.test.ts
		await interactWithCopilotChat();
	} catch (error) {
		throw error;
	}
}

async function downloadSymbols(): Promise<void> {
	vscode.window.showInformationMessage('Downloading symbols...');

	try {
		await vscode.commands.executeCommand('al.downloadSymbols');
		vscode.window.showInformationMessage('Symbols downloaded successfully');
	} catch (error) {
		throw new Error(`Failed to download symbols: ${error}`);
	}
}

async function publishWithoutDebugging(): Promise<void> {
	vscode.window.showInformationMessage('Publishing without debugging...');

	try {
		await vscode.commands.executeCommand('al.publishWithoutDebugging');
		vscode.window.showInformationMessage('Published successfully');
	} catch (error) {
		throw new Error(`Failed to publish: ${error}`);
	}
}

async function interactWithCopilotChat(): Promise<void> {
	try {
		// First, ensure Copilot Chat is available
		const copilotChat = vscode.extensions.getExtension('GitHub.copilot-chat');

		if (!copilotChat) {
			throw new Error('GitHub Copilot Chat extension not found. Please install it first.');
		}

		if (!copilotChat.isActive) {
			await copilotChat.activate();
		}

		// Send the message using Copilot Chat API
		await sendMessageToCopilotAgent('Hello World');

	} catch (error) {
		throw new Error(`Failed to interact with Copilot Chat: ${error}`);
	}
}

/**
 * Sends a message to GitHub Copilot Agent and waits for response
 */
async function sendMessageToCopilotAgent(message: string): Promise<void> {
	try {
		await vscode.commands.executeCommand('workbench.action.chat.newChat');	
		await vscode.commands.executeCommand('workbench.action.chat.open', {
			mode: 'agent',
			query: message,
			modelSelector: {
				vendor: 'copilot',
				id: 'gpt-4o'
			},
			blockOnResponse: true
		});

		// Note: In a real implementation, you might want to:
		// 1. Listen for chat responses using VS Code's chat API
		// 2. Parse the response for specific actions
		// 3. Apply suggested fixes automatically

	} catch (error) {
		throw new Error(`Failed to send message to Copilot Chat: ${error}`);
	}
}

// This method is called when your extension is deactivated
export function deactivate() { }
