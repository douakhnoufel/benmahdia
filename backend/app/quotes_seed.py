"""Starter quotes (PRD 5.2): short, general encouragement with no medical
content. DRAFT: the clinic must read and approve them before the pilot; the
doctor's own quotes and an admin screen come later. Safe to run twice."""

from sqlalchemy import select
from sqlalchemy.orm import Session

from .models import Quote

QUOTES = [
    ("كل يوم تتجاوزه هو انتصار. واصل.", "Chaque jour que vous traversez est une victoire. Continuez."),
    ("الانتكاسة لا تمحو الطريق الذي قطعته.", "Une rechute n'efface pas le chemin parcouru."),
    ("يوماً بعد يوم.", "Un jour à la fois."),
    ("طلب المساعدة علامة قوة.", "Demander de l'aide est un signe de force."),
    ("أنت أقوى من رغبة اللحظة.", "Vous êtes plus fort que l'envie du moment."),
    ("الرغبة تمرّ. تنفّس وانتظر، فهي تبتعد.", "L'envie passe. Respirez et attendez : elle s'éloigne."),
    ("كل خطوة صغيرة لها قيمة.", "Chaque petit pas compte."),
]


def seed_quotes(db: Session) -> None:
    known = set(db.scalars(select(Quote.text_fr)))
    for ar, fr in QUOTES:
        if fr not in known:
            db.add(Quote(text_ar=ar, text_fr=fr))
    db.commit()
