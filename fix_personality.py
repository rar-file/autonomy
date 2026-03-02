import re

with open('templates/index.html', 'r') as f:
    lines = f.readlines()

# Find and replace the personality page section
start_line = None
end_line = None
for i, line in enumerate(lines):
    if 'id="page-personality"' in line:
        start_line = i
    elif start_line and 'id="page-logs"' in line:
        end_line = i
        break

if start_line and end_line:
    # Build new personality section
    new_section = '''                <!-- Personality Page -->
                <div class="page" id="page-personality">
                    <div class="page-header">
                        <h1 class="page-title">Personality Editor</h1>
                        <p class="page-subtitle">Configure AI behavior and suggest changes</p>
                    </div>
                    
                    <div class="personality-editor" style="grid-template-columns: 280px 1fr 320px">
                        <!-- Left: File Explorer -->
                        <div class="file-explorer">
                            <div class="skills-panel-header">
                                <div class="skills-panel-title">Files</div>
                            </div>
                            <div class="file-list" id="personality-file-list">
                                <div class="empty-state" style="padding:1rem"><div style="color:var(--text-muted)">Loading...</div></div>
                            </div>
                        </div>
                        
                        <!-- Middle: Editor -->
                        <div class="editor-pane">
                            <div class="editor-toolbar">
                                <span id="editor-filename" style="font-weight:500">Select a file</span>
                                <button class="btn btn-primary" style="padding:0.4rem 1rem;font-size:0.8rem" onclick="savePersonality()">Save Changes</button>
                            </div>
                            <div class="editor-content">
                                <textarea id="editor-content" placeholder="Select a file from the sidebar to edit..."></textarea>
                            </div>
                        </div>
                        
                        <!-- Right: Suggestions -->
                        <div class="skills-panel" style="max-width:320px">
                            <div class="skills-panel-header">
                                <div class="skills-panel-title">💡 Suggest Changes</div>
                            </div>
                            <div class="skills-panel-body">
                                <p style="font-size:0.85rem;color:var(--text-secondary);margin-bottom:1rem">
                                    Describe changes you'd like to see in the personality. OpenClaw will review and implement them.
                                </p>
                                
                                <select id="suggestion-file" class="workshop-input" style="min-height:44px;margin-bottom:0.75rem">
                                    <option value="">Select target file...</option>
                                    <option value="SOUL.md">SOUL.md - Core personality</option>
                                    <option value="IDENTITY.md">IDENTITY.md - Identity & name</option>
                                    <option value="USER.md">USER.md - User preferences</option>
                                    <option value="AGENTS.md">AGENTS.md - Agent settings</option>
                                    <option value="TOOLS.md">TOOLS.md - Tool preferences</option>
                                </select>
                                
                                <textarea id="suggestion-text" class="workshop-input" placeholder="I think the personality should be more..." style="min-height:150px;margin-bottom:0.75rem"></textarea>
                                
                                <button class="btn btn-primary" onclick="submitSuggestion()" style="width:100%">Submit Suggestion</button>
                                
                                <div id="suggestion-status" style="margin-top:1rem;font-size:0.85rem"></div>
                            </div>
                        </div>
                    </div>
                </div>

'''
    
    # Replace the section
    new_lines = lines[:start_line] + [new_section] + lines[end_line:]
    
    with open('templates/index.html', 'w') as f:
        f.writelines(new_lines)
    
    print('Fixed personality editor section')
else:
    print('Could not find personality section')
