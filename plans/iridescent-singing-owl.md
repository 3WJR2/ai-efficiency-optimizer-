# Azure DevOps AI Chat Extension - Implementation Plan

## Overview
Build an Azure DevOps extension featuring an AI chat interface powered by Azure OpenAI that appears as a persistent right panel. The chat will have access to work items, repositories, and pipelines within the current Azure DevOps project.

## Architecture Summary
- **Type**: Azure DevOps Web Extension
- **UI**: React-based right panel
- **AI Provider**: Azure OpenAI (GPT-4)
- **Architecture**: Client-side only (extension calls Azure OpenAI directly)
- **ADO Integration**: REST API calls for work items, repos, and pipelines
- **Authentication**: Azure DevOps user context + Azure OpenAI API key

## Implementation Steps

### Step 1: Set up Extension Project Structure
**Files to create:**
- `vss-extension.json` - Extension manifest
- `package.json` - NPM dependencies
- `webpack.config.js` - Build configuration
- `tsconfig.json` - TypeScript configuration

**Actions:**
- Initialize npm project with TypeScript, React, and Azure DevOps Extension SDK
- Install dependencies: `azure-devops-extension-sdk`, `azure-devops-extension-api`, `@azure/openai`, `react`, `react-dom`
- Configure webpack to bundle the extension for ADO hosting

### Step 2: Create Extension Manifest
**File: `vss-extension.json`**

Define the extension metadata and contributions:
- Extension ID, name, description, publisher info
- Right panel contribution (`ms.vss-web.tab`) pointing to the chat UI
- Required scopes: `vso.work`, `vso.code`, `vso.build`
- Declare static assets and entry points

### Step 3: Implement Chat UI Component
**Files to create:**
- `src/components/ChatPanel.tsx` - Main panel component
- `src/components/ChatMessage.tsx` - Individual message component
- `src/components/ChatInput.tsx` - Input field with send button
- `src/styles/chat.css` - Styling for chat interface

**Features:**
- Message history display (user messages + AI responses)
- Auto-scroll to latest message
- Loading indicators during AI processing
- Error handling and display
- Markdown rendering for AI responses
- Copy button for code snippets

### Step 4: Create Azure OpenAI Integration Service
**File: `src/services/AzureOpenAIService.ts`**

Implement service to handle Azure OpenAI API calls:
- Configuration management (endpoint, API key, deployment name)
- Chat completion API integration with streaming support
- Message history management
- Error handling and retry logic
- Token usage tracking

### Step 5: Create Azure DevOps Data Access Layer
**Files to create:**
- `src/services/WorkItemService.ts` - Query work items, sprints, backlogs
- `src/services/RepositoryService.ts` - Access repos, files, commits, PRs
- `src/services/PipelineService.ts` - Query builds, releases, logs

**Implementation:**
- Use `azure-devops-extension-api` REST clients
- Initialize ADO SDK with user context
- Implement query methods for each data type
- Format data into context strings for AI prompts
- Handle pagination and rate limiting

### Step 6: Implement Context Builder
**File: `src/services/ContextBuilder.ts`**

Create service to build AI prompts with ADO context:
- Detect intent from user message (e.g., "show me failing builds")
- Fetch relevant ADO data based on intent
- Format data into structured context for AI
- Inject system prompt with ADO context
- Limit context size to stay within token limits

### Step 7: Create Settings Panel
**Files to create:**
- `src/components/SettingsPanel.tsx` - Configuration UI
- `src/services/SettingsService.ts` - Store settings in local storage

**Settings to configure:**
- Azure OpenAI endpoint URL
- API key (stored securely in browser storage)
- Model deployment name
- Temperature and max tokens
- Enable/disable specific ADO data access

### Step 8: Implement Main Panel Integration
**File: `src/index.tsx`**

Set up the extension entry point:
- Initialize Azure DevOps Extension SDK
- Register panel contribution
- Mount React app to container
- Handle panel lifecycle (open, close, resize)
- Apply Azure DevOps theming

### Step 9: Add Advanced Chat Features
**Enhancements:**
- Conversation persistence (save/load from local storage)
- Export chat history
- Clear conversation button
- Context indicators (show which ADO data is being used)
- Suggested prompts/quick actions
- Code syntax highlighting in responses

### Step 10: Build and Package Extension
**Actions:**
- Create build script in `package.json`
- Run webpack to bundle all assets
- Generate `.vsix` package using `tfx-cli`
- Test locally using extension test environment
- Prepare publisher account in Visual Studio Marketplace

### Step 11: Create Documentation
**Files to create:**
- `README.md` - Installation and usage guide
- `docs/setup.md` - Azure OpenAI setup instructions
- `docs/permissions.md` - Required ADO permissions
- `CHANGELOG.md` - Version history

## Critical Files Structure
```
ado-ai-chat-extension/
├── vss-extension.json          # Extension manifest
├── package.json                # Dependencies
├── webpack.config.js           # Build config
├── tsconfig.json               # TypeScript config
├── src/
│   ├── index.tsx               # Entry point
│   ├── components/
│   │   ├── ChatPanel.tsx       # Main chat UI
│   │   ├── ChatMessage.tsx     # Message display
│   │   ├── ChatInput.tsx       # Input field
│   │   └── SettingsPanel.tsx   # Settings UI
│   ├── services/
│   │   ├── AzureOpenAIService.ts      # AI integration
│   │   ├── WorkItemService.ts         # Work items API
│   │   ├── RepositoryService.ts       # Repos API
│   │   ├── PipelineService.ts         # Pipelines API
│   │   ├── ContextBuilder.ts          # Prompt building
│   │   └── SettingsService.ts         # Settings mgmt
│   └── styles/
│       └── chat.css            # Styling
└── dist/                       # Build output
```

## Key Technical Decisions

### Azure OpenAI Configuration
- Use organization's Azure OpenAI endpoint
- API key stored in browser local storage (user-specific)
- Support for GPT-4 and GPT-3.5-turbo deployments
- Streaming responses for better UX

### ADO Data Access Strategy
- Use REST API via `azure-devops-extension-api`
- Leverage user's existing ADO permissions
- Cache frequently accessed data (project info, team info)
- Implement smart context selection to minimize API calls

### Security Considerations
- API keys stored only in browser local storage (never in extension package)
- All ADO API calls use user's authenticated context
- No backend means no shared secrets or server management
- Users responsible for their own Azure OpenAI costs

## Verification Steps

### Development Testing
1. Run `npm install` to install dependencies
2. Run `npm run build` to build the extension
3. Run `npm run serve` to test locally with hot reload
4. Verify extension appears in local ADO test instance

### Functional Testing
1. Open Azure DevOps project in browser
2. Install unpacked extension for testing
3. Open the AI chat panel from the right sidebar
4. Configure Azure OpenAI settings
5. Test basic chat: "Hello, can you help me with my project?"
6. Test work item query: "What work items are in the current sprint?"
7. Test repository query: "Show me recent commits in the main repo"
8. Test pipeline query: "Are there any failing builds?"
9. Verify responses include relevant ADO data
10. Test conversation persistence across page refreshes

### End-to-End Validation
1. Package extension: `tfx extension create --manifest-globs vss-extension.json`
2. Upload to marketplace as private extension
3. Install on real Azure DevOps organization
4. Test all features in production environment
5. Verify theming matches ADO (light/dark modes)
6. Test panel resize and docking behavior
7. Verify token usage stays within Azure OpenAI limits
8. Test error handling (invalid API key, network issues)

## Dependencies to Install
```json
{
  "azure-devops-extension-sdk": "^4.0.0",
  "azure-devops-extension-api": "^4.0.0",
  "@azure/openai": "^1.0.0-beta.12",
  "react": "^18.2.0",
  "react-dom": "^18.2.0",
  "react-markdown": "^9.0.0",
  "typescript": "^5.0.0",
  "webpack": "^5.88.0",
  "webpack-cli": "^5.1.0",
  "tfx-cli": "^0.15.0"
}
```

## Estimated Complexity
- **Core Extension Setup**: Moderate (standard ADO extension patterns)
- **Azure OpenAI Integration**: Low (well-documented API)
- **ADO Data Access**: Moderate (REST API complexity varies by data type)
- **Context Building**: High (requires intelligent prompt engineering)
- **UI/UX**: Moderate (React components with ADO theming)

## Next Steps After Implementation
1. Add support for writing to ADO (create work items, update status)
2. Implement RAG (Retrieval Augmented Generation) for code search
3. Add conversation templates for common scenarios
4. Support multiple simultaneous conversations
5. Add team collaboration features (share conversations)
6. Implement analytics dashboard (usage, costs, common queries)
