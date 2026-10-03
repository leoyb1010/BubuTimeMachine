# School journal scroll viewport

The school journal hides the system navigation bar but retains the system status
bar. Scrolling report content must stay inside the content viewport; temperatures,
icons and text must not paint behind the time, wireless indicator or battery.
The paper/theme background can still extend through the safe area.

The fix clips only the school journal's scroll container, before applying its
full-screen background. It does not alter report data, card sizes, scroll range,
root tabs or other pages. Verify the actual scrolled journal screenshot on both
iPhone and iPad, as well as the existing root-navigation and every-report-group
journeys. Source inspection alone does not establish the visible result.
