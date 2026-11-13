configuration {
  show-icons: true;
}
* {
  bg: {{ background }};
  fg: {{ foreground }};
  accent: {{ accent }};
  sel-fg: {{ selection_foreground }};
  background-color: transparent;
  text-color: @fg;
  font: "JetBrainsMono Nerd Font 11";
}
window {
  location: center;
  width: 1180px;
  background-color: @bg;
  border: 2px;
  border-color: @accent;
  border-radius: 0;
  padding: 18px;
}
mainbox { children: [ inputbar, listview ]; spacing: 14px; }
inputbar { children: [ prompt, entry ]; spacing: 10px; padding: 4px 6px; }
prompt { text-color: @accent; }
entry { placeholder: "type to filter · enter to keep · esc to revert"; placeholder-color: {{ color8 }}; }
listview {
  columns: 4;
  lines: 3;
  fixed-columns: true;
  flow: horizontal;
  spacing: 12px;
  scrollbar: false;
  cycle: true;
}
element {
  orientation: vertical;
  padding: 8px;
  spacing: 6px;
  border: 2px;
  border-color: transparent;
  border-radius: 0;
}
element selected { border-color: @accent; background-color: @accent; text-color: @sel-fg; }
element-icon { size: 250px; horizontal-align: 0.5; }
element-text { horizontal-align: 0.5; text-color: inherit; }
