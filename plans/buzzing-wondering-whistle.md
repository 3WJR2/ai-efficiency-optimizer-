# Port Qodo Gen Chat UI to Azure DevOps Extension

## Context

The user has built an Azure DevOps extension with solid service layer (WorkItemService, PullRequestService, KnowledgeService, etc.) but wants to replace the current simple UI with the sophisticated qodo-gen-chat-webview design that includes:

- **Rich TipTap editor** with @mentions and image paste
- **Radix UI component library** for polished UI
- **Modular CSS architecture** with smooth animations
- **Context management system** for file attachments and extra context
- **Model selection and conversation mode toggles**

**Current State:**
- Service layer: ✅ Complete and working (9 services, ~100KB)
- UI components: ❌ Basic React components with plain CSS
- Styling: ❌ Simple CSS, no animations
- Editor: ❌ Basic HTML textarea

**Goal:**
Port the full qodo-gen-chat UI architecture to Azure DevOps while preserving all existing ADO service integration.

**Scope:**
This is a MAJOR architectural change (~2-3 days of work). The plan breaks it down into manageable phases with clear verification points.

---

## Implementation Strategy

### Phase 1: Dependencies & Build Setup (Est: 2 hours)

**Add new dependencies to package.json:**

```json
{
  "dependencies": {
    "@radix-ui/themes": "^3.0.0",
    "@radix-ui/react-dialog": "^1.0.5",
    "@radix-ui/react-dropdown-menu": "^2.0.6",
    "@radix-ui/react-tooltip": "^1.0.7",
    "@radix-ui/react-select": "^2.0.0",
    "@tiptap/react": "^2.1.13",
    "@tiptap/starter-kit": "^2.1.13",
    "@tiptap/extension-placeholder": "^2.1.13",
    "@tiptap/extension-mention": "^2.1.13",
    "@tiptap/extension-image": "^2.1.13",
    "lucide-react": "^0.292.0"
  }
}
```

**Files to modify:**
- `/Users/wallonwalusayi/Desktop/Qodo/Codebase/ado-ai-chat-extension/package.json`

**Verification:**
```bash
cd "/Users/wallonwalusayi/Desktop/Qodo/Codebase/ado-ai-chat-extension"
npm install
npm run build  # Should complete without errors
```

---

### Phase 2: Theme Adaptation (Est: 3 hours)

**Create ADO theme adapter** to map VSCode variables to Fabric UI colors.

**New file:** `/src/styles/ado-theme.css`

```css
/* Azure DevOps Theme Variables */
:root {
  /* Primary Colors */
  --ado-primary: #0078d4;
  --ado-primary-hover: #106ebe;
  --ado-primary-active: #005a9e;

  /* Backgrounds */
  --ado-bg-primary: #ffffff;
  --ado-bg-secondary: #f3f2f1;
  --ado-bg-tertiary: #edebe9;

  /* Text */
  --ado-text-primary: #323130;
  --ado-text-secondary: #605e5c;
  --ado-text-disabled: #a19f9d;

  /* Borders */
  --ado-border: #edebe9;
  --ado-border-focus: #0078d4;

  /* Status Colors */
  --ado-success: #107c10;
  --ado-warning: #f7630c;
  --ado-error: #d13438;
  --ado-info: #0078d4;
}

/* Dark theme overrides (ADO dark mode) */
[data-theme="dark"] {
  --ado-bg-primary: #1b1a19;
  --ado-bg-secondary: #252423;
  --ado-bg-tertiary: #323130;
  --ado-text-primary: #ffffff;
  --ado-text-secondary: #d2d0ce;
  --ado-text-disabled: #8a8886;
  --ado-border: #323130;
}
```

**Copy and adapt core styling from original:**

1. Copy `/Qodo/Codebase/qodo-gen-chat-webview-main/src/styles/App.css` → `/ado-ai-chat-extension/src/styles/App.css`
2. Copy `/qodo-gen-chat-webview-main/src/styles/colors.css` → `/ado-ai-chat-extension/src/styles/colors.css`
3. Replace all `var(--vscode-*)` with `var(--ado-*)`

**Files to create/modify:**
- `/src/styles/ado-theme.css` (NEW)
- `/src/styles/App.css` (REPLACE)
- `/src/styles/colors.css` (REPLACE)
- `/src/index.tsx` (import ado-theme.css)

**Verification:**
```typescript
// In browser devtools, check computed styles
const root = document.documentElement;
const primary = getComputedStyle(root).getPropertyValue('--ado-primary');
console.log('Primary color:', primary); // Should be #0078d4
```

---

### Phase 3: Context Provider Architecture (Est: 4 hours)

**Create ADO-specific context provider** replacing VSCode IDE context with Azure DevOps context.

**New file:** `/src/context/ADOContext.tsx`

```typescript
import React, { createContext, useContext, useState, useEffect } from 'react';
import * as SDK from 'azure-devops-extension-sdk';
import { IProjectPageService, CommonServiceIds } from 'azure-devops-extension-api';

interface ADOContextType {
  project: Project | null;
  repository: GitRepository | null;
  currentUser: IdentityRef | null;
  isInitialized: boolean;
}

const ADOContext = createContext<ADOContextType | null>(null);

export const ADOContextProvider: React.FC<{ children: React.ReactNode }> = ({ children }) => {
  const [context, setContext] = useState<ADOContextType>({
    project: null,
    repository: null,
    currentUser: null,
    isInitialized: false
  });

  useEffect(() => {
    const initialize = async () => {
      try {
        await SDK.ready();

        const projectService = await SDK.getService<IProjectPageService>(
          CommonServiceIds.ProjectPageService
        );
        const project = await projectService.getProject();

        const userService = await SDK.getService<ILocationService>(
          CommonServiceIds.LocationService
        );
        const user = SDK.getUser();

        setContext({
          project: project || null,
          repository: null, // Will be set when repo context available
          currentUser: user,
          isInitialized: true
        });
      } catch (error) {
        console.error('[ADOContext] Initialization failed:', error);
      }
    };

    initialize();
  }, []);

  return <ADOContext.Provider value={context}>{children}</ADOContext.Provider>;
};

export const useADOContext = () => {
  const context = useContext(ADOContext);
  if (!context) {
    throw new Error('useADOContext must be used within ADOContextProvider');
  }
  return context;
};
```

**Create Chat Context Provider** (adapting from original):

**New file:** `/src/context/ChatContext.tsx`

```typescript
import React, { createContext, useContext, useState, useCallback } from 'react';
import { Message, Settings } from '../types';

interface ChatContextType {
  messages: Message[];
  isLoading: boolean;
  settings: Settings | null;
  addMessage: (message: Message) => void;
  clearMessages: () => void;
  setLoading: (loading: boolean) => void;
  updateSettings: (settings: Settings) => void;
}

const ChatContext = createContext<ChatContextType | null>(null);

export const ChatContextProvider: React.FC<{ children: React.ReactNode }> = ({ children }) => {
  const [messages, setMessages] = useState<Message[]>([]);
  const [isLoading, setIsLoading] = useState(false);
  const [settings, setSettings] = useState<Settings | null>(null);

  const addMessage = useCallback((message: Message) => {
    setMessages(prev => [...prev, message]);
  }, []);

  const clearMessages = useCallback(() => {
    setMessages([]);
  }, []);

  const updateSettings = useCallback((newSettings: Settings) => {
    setSettings(newSettings);
    localStorage.setItem('ado-ai-chat-settings', JSON.stringify(newSettings));
  }, []);

  const value = {
    messages,
    isLoading,
    settings,
    addMessage,
    clearMessages,
    setLoading: setIsLoading,
    updateSettings
  };

  return <ChatContext.Provider value={value}>{children}</ChatContext.Provider>;
};

export const useChatContext = () => {
  const context = useContext(ChatContext);
  if (!context) {
    throw new Error('useChatContext must be used within ChatContextProvider');
  }
  return context;
};
```

**Files to create:**
- `/src/context/ADOContext.tsx` (NEW)
- `/src/context/ChatContext.tsx` (NEW)
- `/src/context/index.tsx` (NEW - exports both)

**Files to modify:**
- `/src/App.tsx` - Wrap with providers:
  ```tsx
  <ADOContextProvider>
    <ChatContextProvider>
      {/* existing components */}
    </ChatContextProvider>
  </ADOContextProvider>
  ```

**Verification:**
```typescript
// In any component:
const { project, isInitialized } = useADOContext();
console.log('Project:', project?.name);
console.log('Initialized:', isInitialized);
```

---

### Phase 4: TipTap Editor Integration (Est: 5 hours)

**Create custom TipTap editor with ADO-specific features.**

**New file:** `/src/components/editor/CodiumChatEditor.tsx`

```typescript
import { useEditor, EditorContent } from '@tiptap/react';
import StarterKit from '@tiptap/starter-kit';
import Placeholder from '@tiptap/extension-placeholder';
import Mention from '@tiptap/extension-mention';
import Image from '@tiptap/extension-image';
import React from 'react';
import styles from './CodiumChatEditor.module.css';

interface CodiumChatEditorProps {
  onSubmit: (content: string) => void;
  placeholder?: string;
  disabled?: boolean;
}

export const CodiumChatEditor: React.FC<CodiumChatEditorProps> = ({
  onSubmit,
  placeholder = 'Ask anything...',
  disabled = false
}) => {
  const editor = useEditor({
    extensions: [
      StarterKit,
      Placeholder.configure({ placeholder }),
      Mention.configure({
        HTMLAttributes: {
          class: 'mention',
        },
        suggestion: {
          items: ({ query }) => {
            // ADO-specific mentions: work items, PRs, users
            return [
              { id: 'workitem', label: 'Work Item' },
              { id: 'pr', label: 'Pull Request' },
              { id: 'user', label: 'User' },
            ].filter(item => item.label.toLowerCase().includes(query.toLowerCase()));
          },
        },
      }),
      Image.configure({
        inline: true,
        allowBase64: true,
      }),
    ],
    editorProps: {
      attributes: {
        class: 'codium-editor',
      },
    },
    onUpdate: ({ editor }) => {
      // Auto-resize logic
    },
  });

  const handleKeyDown = (event: React.KeyboardEvent) => {
    if (event.key === 'Enter' && !event.shiftKey && !disabled) {
      event.preventDefault();
      const content = editor?.getHTML() || '';
      if (content.trim()) {
        onSubmit(content);
        editor?.commands.clearContent();
      }
    }
  };

  return (
    <div className={styles.editorContainer} onKeyDown={handleKeyDown}>
      <EditorContent editor={editor} disabled={disabled} />
    </div>
  );
};
```

**New file:** `/src/components/editor/CodiumChatEditor.module.css`

```css
.editorContainer {
  position: relative;
  border: 1px solid var(--ado-border);
  border-radius: 8px;
  min-height: 52px;
  max-height: 200px;
  overflow-y: auto;
  padding: 12px;
  background: var(--ado-bg-primary);
  transition: border-color 0.2s ease;
}

.editorContainer:focus-within {
  border-color: var(--ado-primary);
  box-shadow: 0 0 0 1px var(--ado-primary);
}

.editorContainer :global(.ProseMirror) {
  outline: none;
  font-size: 14px;
  line-height: 1.5;
  color: var(--ado-text-primary);
}

.editorContainer :global(.ProseMirror p.is-editor-empty:first-child::before) {
  content: attr(data-placeholder);
  color: var(--ado-text-disabled);
  pointer-events: none;
  height: 0;
}

.editorContainer :global(.mention) {
  background-color: var(--ado-primary);
  color: white;
  padding: 2px 6px;
  border-radius: 4px;
  font-weight: 500;
}
```

**Files to create:**
- `/src/components/editor/CodiumChatEditor.tsx` (NEW)
- `/src/components/editor/CodiumChatEditor.module.css` (NEW)
- `/src/components/editor/index.tsx` (NEW - export)

**Verification:**
```typescript
// In ChatPanel, replace EnhancedChatInput with:
<CodiumChatEditor
  onSubmit={handleSendMessage}
  placeholder="Ask about work items, PRs, code..."
  disabled={isLoading}
/>
```

Test:
- Type text and press Enter → Should submit
- Type with Shift+Enter → Should create new line
- Type @ → Should show mention suggestions

---

### Phase 5: User Input Component (Est: 3 hours)

**Port the sophisticated Input component** from original with context management.

**New file:** `/src/components/user_input/Input.tsx`

```typescript
import { Flex } from '@radix-ui/themes';
import { Editor } from '@tiptap/react';
import React, { useState } from 'react';
import { CodiumChatEditor } from '../editor/CodiumChatEditor';
import { useChatContext } from '../../context';
import SendStopButton from './parts/SendStopButton';
import ModelSelection from './ModelSelection';
import FileAttachmentDisplay from './parts/FileAttachmentDisplay';
import styles from './Input.module.css';

interface InputProps {
  onSubmit: (content: string) => void;
}

export const Input: React.FC<InputProps> = ({ onSubmit }) => {
  const { isLoading, settings } = useChatContext();
  const [attachedFiles, setAttachedFiles] = useState<File[]>([]);

  const handleSubmit = (content: string) => {
    if (!isLoading && content.trim()) {
      onSubmit(content);
    }
  };

  return (
    <Flex direction="column" gap="2" className={styles.inputContainer}>
      <FileAttachmentDisplay
        files={attachedFiles}
        onRemove={(index) => {
          setAttachedFiles(prev => prev.filter((_, i) => i !== index));
        }}
      />

      <div className={styles.editorWrapper}>
        <CodiumChatEditor
          onSubmit={handleSubmit}
          placeholder="Ask anything about your Azure DevOps project..."
          disabled={isLoading}
        />
      </div>

      <Flex direction="row" justify="between" align="center" className={styles.toolbar}>
        <ModelSelection />
        <SendStopButton
          disabled={isLoading}
          onSend={() => {
            // Trigger editor submit
          }}
        />
      </Flex>
    </Flex>
  );
};
```

**New file:** `/src/components/user_input/Input.module.css`

```css
.inputContainer {
  padding: 16px;
  background: var(--ado-bg-secondary);
  border-top: 1px solid var(--ado-border);
}

.editorWrapper {
  flex: 1;
}

.toolbar {
  padding-top: 8px;
}
```

**Files to create:**
- `/src/components/user_input/Input.tsx` (NEW)
- `/src/components/user_input/Input.module.css` (NEW)
- `/src/components/user_input/ModelSelection.tsx` (NEW - adapted from original)
- `/src/components/user_input/parts/SendStopButton.tsx` (NEW)
- `/src/components/user_input/parts/FileAttachmentDisplay.tsx` (NEW)

**Files to modify:**
- `/src/components/ChatPanel.tsx` - Replace EnhancedChatInput with Input

**Verification:**
- Input should render with editor
- Model selection dropdown should work
- Send button should be disabled when loading
- File attachments should display

---

### Phase 6: Radix UI Component Library Integration (Est: 4 hours)

**Create core UI components using Radix UI primitives.**

**New file:** `/src/components/common/Button.tsx`

```typescript
import React from 'react';
import * as RadixButton from '@radix-ui/react-button';
import styles from './Button.module.css';

interface ButtonProps extends React.ComponentProps<typeof RadixButton.Root> {
  variant?: 'primary' | 'secondary' | 'ghost';
  size?: 'small' | 'medium' | 'large';
}

export const Button: React.FC<ButtonProps> = ({
  variant = 'primary',
  size = 'medium',
  children,
  className,
  ...props
}) => {
  return (
    <RadixButton.Root
      className={`${styles.button} ${styles[variant]} ${styles[size]} ${className}`}
      {...props}
    >
      {children}
    </RadixButton.Root>
  );
};
```

**Similar components to create:**
- `/src/components/common/Dialog.tsx` - Modal dialogs (replaces SettingsPanel)
- `/src/components/common/Dropdown.tsx` - Dropdowns (for model selection)
- `/src/components/common/Tooltip.tsx` - Tooltips
- `/src/components/common/Select.tsx` - Select menus

**Modular CSS pattern:**
Each component gets a `.module.css` file for scoped styling.

**Files to create:**
- `/src/components/common/Button.tsx` + `.module.css`
- `/src/components/common/Dialog.tsx` + `.module.css`
- `/src/components/common/Dropdown.tsx` + `.module.css`
- `/src/components/common/Tooltip.tsx` + `.module.css`
- `/src/components/common/Select.tsx` + `.module.css`

**Files to modify:**
- All existing components to use new Radix UI components

**Verification:**
- Each component should render with correct styling
- Interactions (clicks, hovers) should work smoothly
- Accessibility (keyboard navigation, ARIA) should be maintained

---

### Phase 7: Settings UI Redesign (Est: 2 hours)

**Replace SettingsPanel with Radix UI Dialog.**

**New file:** `/src/components/settings/SettingsDialog.tsx`

```typescript
import React from 'react';
import * as Dialog from '@radix-ui/react-dialog';
import { Flex, Text } from '@radix-ui/themes';
import { X } from 'lucide-react';
import { useChatContext } from '../../context';
import styles from './SettingsDialog.module.css';

interface SettingsDialogProps {
  open: boolean;
  onOpenChange: (open: boolean) => void;
}

export const SettingsDialog: React.FC<SettingsDialogProps> = ({ open, onOpenChange }) => {
  const { settings, updateSettings } = useChatContext();

  return (
    <Dialog.Root open={open} onOpenChange={onOpenChange}>
      <Dialog.Portal>
        <Dialog.Overlay className={styles.overlay} />
        <Dialog.Content className={styles.content}>
          <Flex direction="column" gap="4">
            <Flex justify="between" align="center">
              <Dialog.Title className={styles.title}>Settings</Dialog.Title>
              <Dialog.Close className={styles.closeButton}>
                <X size={20} />
              </Dialog.Close>
            </Flex>

            {/* Settings form content */}
            <div className={styles.formGroup}>
              <label>AI Provider</label>
              <select value={settings?.aiProvider} onChange={/* ... */}>
                <option value="openai">OpenAI</option>
                <option value="azure">Azure OpenAI</option>
              </select>
            </div>

            {/* More fields... */}

            <Flex gap="2" justify="end">
              <Dialog.Close asChild>
                <button className={styles.cancelButton}>Cancel</button>
              </Dialog.Close>
              <button className={styles.saveButton} onClick={/* save */}>
                Save
              </button>
            </Flex>
          </Flex>
        </Dialog.Content>
      </Dialog.Portal>
    </Dialog.Root>
  );
};
```

**Files to create:**
- `/src/components/settings/SettingsDialog.tsx` (NEW)
- `/src/components/settings/SettingsDialog.module.css` (NEW)

**Files to remove/replace:**
- `/src/components/SettingsPanel.tsx` (REPLACE functionality)
- `/src/styles/settings.css` (REPLACE with modular CSS)

**Verification:**
- Settings dialog should open/close smoothly
- Form validation should work
- Settings should persist to localStorage
- All existing settings options should be available

---

### Phase 8: Message Display Components (Est: 3 hours)

**Enhance message display with animations and better styling.**

**New file:** `/src/components/chat/ChatMessage.tsx`

```typescript
import React from 'react';
import { Flex, Text } from '@radix-ui/themes';
import ReactMarkdown from 'react-markdown';
import { Prism as SyntaxHighlighter } from 'react-syntax-highlighter';
import { oneDark } from 'react-syntax-highlighter/dist/esm/styles/prism';
import { Message } from '../../types';
import styles from './ChatMessage.module.css';

interface ChatMessageProps {
  message: Message;
}

export const ChatMessage: React.FC<ChatMessageProps> = ({ message }) => {
  return (
    <div className={`${styles.message} ${styles[message.sender]}`}>
      <Flex direction="column" gap="2">
        <Text size="1" color="gray" className={styles.timestamp}>
          {new Date(message.timestamp).toLocaleTimeString()}
        </Text>

        <div className={styles.content}>
          <ReactMarkdown
            components={{
              code({ node, inline, className, children, ...props }) {
                const match = /language-(\w+)/.exec(className || '');
                return !inline && match ? (
                  <SyntaxHighlighter
                    style={oneDark}
                    language={match[1]}
                    PreTag="div"
                    {...props}
                  >
                    {String(children).replace(/\n$/, '')}
                  </SyntaxHighlighter>
                ) : (
                  <code className={className} {...props}>
                    {children}
                  </code>
                );
              },
            }}
          >
            {message.text}
          </ReactMarkdown>
        </div>
      </Flex>
    </div>
  );
};
```

**New file:** `/src/components/chat/ChatMessage.module.css`

```css
.message {
  padding: 16px;
  margin: 8px 0;
  border-radius: 8px;
  animation: messageSlideIn 0.3s ease-out;
  will-change: transform, opacity;
}

@keyframes messageSlideIn {
  from {
    opacity: 0;
    transform: translateY(10px);
  }
  to {
    opacity: 1;
    transform: translateY(0);
  }
}

.user {
  background: var(--ado-bg-tertiary);
  margin-left: 40px;
}

.assistant {
  background: var(--ado-bg-secondary);
  margin-right: 40px;
}

.content {
  line-height: 1.6;
  color: var(--ado-text-primary);
}

.timestamp {
  font-size: 12px;
  color: var(--ado-text-secondary);
}
```

**Files to create/modify:**
- `/src/components/chat/ChatMessage.tsx` (REPLACE)
- `/src/components/chat/ChatMessage.module.css` (NEW)

**Verification:**
- Messages should animate in smoothly
- Code blocks should have syntax highlighting
- Markdown should render correctly
- Timestamps should be formatted properly

---

### Phase 9: Integration & Testing (Est: 4 hours)

**Wire everything together and test end-to-end.**

**Modify App.tsx:**

```typescript
import '@radix-ui/themes/styles.css';
import './styles/ado-theme.css';
import './styles/App.css';
import './styles/colors.css';
import React from 'react';
import { Theme } from '@radix-ui/themes';
import { ADOContextProvider } from './context/ADOContext';
import { ChatContextProvider } from './context/ChatContext';
import { Chat } from './pages/Chat';
import { SettingsDialog } from './components/settings/SettingsDialog';

const App = () => {
  const [settingsOpen, setSettingsOpen] = React.useState(false);

  return (
    <Theme>
      <ADOContextProvider>
        <ChatContextProvider>
          <Chat onOpenSettings={() => setSettingsOpen(true)} />
          <SettingsDialog open={settingsOpen} onOpenChange={setSettingsOpen} />
        </ChatContextProvider>
      </ADOContextProvider>
    </Theme>
  );
};

export default App;
```

**Modify Chat.tsx (main page):**

```typescript
import React from 'react';
import { Flex } from '@radix-ui/themes';
import { Input } from '../components/user_input/Input';
import { ChatMessage } from '../components/chat/ChatMessage';
import { useChatContext, useADOContext } from '../context';
import { OpenAIService } from '../services/OpenAIService';
import { ContextBuilder } from '../services/ContextBuilder';
import styles from './Chat.module.css';

export const Chat: React.FC<{ onOpenSettings: () => void }> = ({ onOpenSettings }) => {
  const { messages, isLoading, settings, addMessage, setLoading } = useChatContext();
  const { project, isInitialized } = useADOContext();

  const handleSubmit = async (content: string) => {
    if (!settings || !project || !isInitialized) {
      console.error('Not initialized');
      return;
    }

    const userMessage = {
      id: Date.now().toString(),
      sender: 'user' as const,
      text: content,
      timestamp: new Date(),
    };
    addMessage(userMessage);
    setLoading(true);

    try {
      // Use existing ContextBuilder and OpenAIService
      const contextBuilder = new ContextBuilder(settings);
      await contextBuilder.initialize();

      const context = await contextBuilder.buildMultiSourceContext(content);
      const openAIService = new OpenAIService(settings.openai);

      const response = await openAIService.sendMessage(
        [...messages, userMessage],
        context
      );

      addMessage({
        id: (Date.now() + 1).toString(),
        sender: 'assistant',
        text: response,
        timestamp: new Date(),
      });
    } catch (error) {
      console.error('Error:', error);
      addMessage({
        id: (Date.now() + 1).toString(),
        sender: 'assistant',
        text: 'Sorry, an error occurred.',
        timestamp: new Date(),
      });
    } finally {
      setLoading(false);
    }
  };

  return (
    <Flex direction="column" className={styles.chat}>
      <div className={styles.messagesContainer}>
        {messages.map(msg => (
          <ChatMessage key={msg.id} message={msg} />
        ))}
      </div>
      <Input onSubmit={handleSubmit} />
    </Flex>
  );
};
```

**Files to modify:**
- `/src/App.tsx` (MAJOR REFACTOR)
- `/src/pages/Chat.tsx` (MAJOR REFACTOR)
- `/src/index.tsx` (ensure Radix CSS is imported)

**Verification:**

1. **Build test:**
   ```bash
   npm run build
   # Should complete with 0 errors
   ```

2. **Runtime test:**
   - Extension loads in ADO
   - Chat interface renders
   - Can type in editor (TipTap)
   - Can send message
   - Message appears in history
   - AI responds correctly
   - Settings dialog opens/closes
   - Theme adapts to ADO light/dark mode

3. **Service integration test:**
   - Work item queries work
   - PR queries work
   - Knowledge search works
   - Context builder aggregates correctly

4. **UI interaction test:**
   - Smooth animations (60fps)
   - No layout shifts
   - Responsive to window resize
   - Keyboard shortcuts work
   - Accessibility features work

---

## Critical Files Summary

**Files to create (NEW):**
- `/src/context/ADOContext.tsx`
- `/src/context/ChatContext.tsx`
- `/src/context/index.tsx`
- `/src/components/editor/CodiumChatEditor.tsx`
- `/src/components/editor/CodiumChatEditor.module.css`
- `/src/components/user_input/Input.tsx`
- `/src/components/user_input/Input.module.css`
- `/src/components/user_input/ModelSelection.tsx`
- `/src/components/user_input/parts/SendStopButton.tsx`
- `/src/components/user_input/parts/FileAttachmentDisplay.tsx`
- `/src/components/common/Button.tsx` + `.module.css`
- `/src/components/common/Dialog.tsx` + `.module.css`
- `/src/components/common/Dropdown.tsx` + `.module.css`
- `/src/components/common/Tooltip.tsx` + `.module.css`
- `/src/components/common/Select.tsx` + `.module.css`
- `/src/components/settings/SettingsDialog.tsx`
- `/src/components/settings/SettingsDialog.module.css`
- `/src/styles/ado-theme.css`

**Files to modify (REFACTOR):**
- `/src/App.tsx` - Add providers, Radix Theme wrapper
- `/src/pages/Chat.tsx` - Replace components, use contexts
- `/src/components/chat/ChatMessage.tsx` - Enhance styling, animations
- `/src/index.tsx` - Import Radix CSS
- `package.json` - Add dependencies

**Files to preserve (NO CHANGES):**
- `/src/services/*.ts` - All service files (9 files)
- `/src/types.ts` - Type definitions
- `webpack.config.js` - Build config
- `vss-extension.json` - Extension manifest

**Files to remove (DEPRECATED):**
- `/src/components/EnhancedChatInput.tsx` - Replaced by Input + CodiumChatEditor
- `/src/components/SettingsPanel.tsx` - Replaced by SettingsDialog
- `/src/components/Sidebar.tsx` - Will be integrated into new layout
- `/src/styles/chat.css` - Replaced by modular CSS
- `/src/styles/settings.css` - Replaced by modular CSS
- `/src/styles/qodo-theme.css` - Replaced by ado-theme.css

---

## Risk Assessment

**HIGH RISK:**
- Complete UI overhaul could introduce regressions
- Service integration might break if not carefully tested
- Build configuration changes could affect deployment

**MEDIUM RISK:**
- TipTap editor complexity
- Theme adaptation edge cases
- Radix UI learning curve

**LOW RISK:**
- Service layer preserved (no changes)
- Existing functionality tested separately
- Incremental migration possible

---

## Rollback Plan

If issues arise:

1. **Phase-level rollback:** Each phase is self-contained
2. **Git branch strategy:** Create `feature/port-ui` branch
3. **Package backup:** Keep old VSIX as backup
4. **Service preservation:** Services unchanged, so core functionality intact

---

## Success Criteria

✅ Extension builds without errors
✅ All services (WorkItem, PR, Knowledge, etc.) still functional
✅ TipTap editor works with @mentions
✅ Radix UI components render correctly
✅ ADO theme adapts to light/dark mode
✅ Smooth 60fps animations
✅ Settings persist correctly
✅ AI responses display properly
✅ No console errors in browser
✅ Passes manual testing checklist

---

## Estimated Timeline

- **Phase 1:** 2 hours
- **Phase 2:** 3 hours
- **Phase 3:** 4 hours
- **Phase 4:** 5 hours
- **Phase 5:** 3 hours
- **Phase 6:** 4 hours
- **Phase 7:** 2 hours
- **Phase 8:** 3 hours
- **Phase 9:** 4 hours

**Total:** ~30 hours (3-4 days of focused work)

**Recommendation:** Execute phases 1-3 first (foundation), then test thoroughly before continuing with phases 4-9 (UI components).

---

## Alternative Approach (If Scope Too Large)

**Minimal Viable Port (MVP):**
1. Keep current simple UI
2. Add only TipTap editor (Phase 4)
3. Add Radix UI buttons/dialogs (subset of Phase 6)
4. Skip complex context management
5. Gradual enhancement over time

**Estimated MVP:** ~10 hours (1-2 days)

---

This plan provides a complete roadmap for porting the sophisticated qodo-gen-chat UI to the Azure DevOps extension while preserving all existing service layer functionality.
