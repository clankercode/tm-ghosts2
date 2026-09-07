// Tooltip helper (pattern from E++ / Dips++): wrapped text in a tooltip window with an explicit width, so a long
// message never produces ImGui's one-word-per-line auto-fit layout. Short messages keep a snug width.

const float TooltipMaxWidth = 400.0f;

void AddSimpleTooltip(const string &in msg) {
    if (!UI::IsItemHovered()) return;
    float w = Math::Min(TooltipMaxWidth, UI::MeasureString(msg).x + 20.0f);
    UI::SetNextWindowSize(int(w), 0, UI::Cond::Always);
    UI::BeginTooltip();
    UI::TextWrapped(msg);
    UI::EndTooltip();
}
