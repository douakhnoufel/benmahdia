"""The clinic's list of good habits to replace using (PRD 5.6), in both app
languages. A reminder for one of these names it; a habit in the patient's
own words ("custom") gets only a neutral reminder, scheduled by the phone."""

from .models import HabitKind
from .substances import Text

HABITS: dict[HabitKind, Text] = {
    HabitKind.sport: Text("الرياضة أو المشي", "Sport ou marche"),
    HabitKind.brush_teeth: Text("تنظيف الأسنان", "Se brosser les dents"),
    HabitKind.water: Text("شرب الماء", "Boire de l'eau"),
    HabitKind.reading: Text("القراءة", "Lire"),
    HabitKind.call_family: Text("الاتصال بالعائلة", "Appeler la famille"),
    HabitKind.sleep: Text("النوم في الوقت", "Se coucher à l'heure"),
}
