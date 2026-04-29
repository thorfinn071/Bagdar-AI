"""
Build deposit-copy PDF of source code for НИИС РК copyright application.

Generates a single PDF containing:
  - title page (work name, author, year, languages);
  - table of contents;
  - "Часть I" — initial modules (entry point + UI screens);
  - "Часть II" — closing modules (core algorithms / services);
  - page numbers, file headers, line numbers, monospace font.

Usage:
    pip install fpdf2
    python tools/build_source_deposit.py

Adjust FILES_FIRST_PART / FILES_LAST_PART / MAX_LINES_PER_FILE below
to fit the desired total page count (target: ~50–60 pages).
"""

from __future__ import annotations

import sys
from datetime import datetime
from pathlib import Path

try:
    from fpdf import FPDF
    from fpdf.enums import XPos, YPos
except ImportError:
    sys.stderr.write("Error: fpdf2 not installed.\nRun: pip install fpdf2\n")
    sys.exit(1)

_NEXT = {'new_x': XPos.LMARGIN, 'new_y': YPos.NEXT}

# Glyphs absent from Consolas — replace with ASCII-safe equivalents.
_GLYPH_FALLBACK = {
    '\u25c0': '<',  # ◀
    '\u25b6': '>',  # ▶
    '\u25b2': '^',  # ▲
    '\u25bc': 'v',  # ▼
    '\u2190': '<-',
    '\u2192': '->',
    '\u2191': '^',
    '\u2193': 'v',
    '\u2713': '+',  # ✓
    '\u2717': 'x',  # ✗
    '\u00a0': ' ',  # NBSP
}


def sanitize(text: str) -> str:
    for k, v in _GLYPH_FALLBACK.items():
        if k in text:
            text = text.replace(k, v)
    return text


# =====================================================================
# CONFIGURATION — edit values below to match your application data
# =====================================================================

ROOT = Path(__file__).resolve().parent.parent

WORK_TITLE = 'Bagdar — ассистивная система навигации для лиц с нарушениями зрения'
WORK_TYPE = 'Программа для ЭВМ'
VERSION = '1.0.0'
AUTHORS = 'Сәбит Нұрмұхамед Жандосұлы'
RIGHTHOLDER = 'Сәбит Нұрмұхамед Жандосұлы'
YEAR_CREATED = datetime.now().year
LANGUAGES = 'Dart (Flutter), Kotlin'
CITY = 'Астана'

# Files to include in the FIRST part of the deposit.
# Goal: identify the work (entry point, main UI flow).
FILES_FIRST_PART: list[str] = [
    'lib/main.dart',
    'lib/onboarding_screen.dart',
    'lib/gesture_tutorial_screen.dart',
    'lib/camera_screen.dart',          # very large — capped via MAX_LINES_PER_FILE
]

# Files to include in the LAST part of the deposit.
# Goal: demonstrate originality (unique algorithms / services).
FILES_LAST_PART: list[str] = [
    'lib/services/fall_detector.dart',
    'lib/services/traffic_light_analyzer.dart',
    'lib/services/motion_prealert.dart',
    'lib/services/ncnn_depth_provider.dart',
    'lib/services/ch_router.dart',
    'lib/services/indoor_gate.dart',
    'lib/services/tts_service.dart',
    'lib/camera/depth_pipeline_controller.dart',
    'lib/camera/alert_manager.dart',
]

# Optional per-file line cap. If a file is longer, it is truncated and an
# ellipsis line is added at the end. Use it to keep oversized files
# (e.g. camera_screen.dart, ~1600 lines) under control.
MAX_LINES_PER_FILE: dict[str, int] = {
    'lib/camera_screen.dart': 400,
    'lib/services/navigation_service.dart': 300,
    'lib/services/voice_command_service.dart': 300,
}

OUTPUT = ROOT / 'bagdar_source_deposit.pdf'

# Font (must be a Unicode TTF, otherwise Cyrillic will not render).
FONT_REGULAR = Path(r'C:\Windows\Fonts\consola.ttf')   # Consolas
FONT_BOLD = Path(r'C:\Windows\Fonts\consolab.ttf')

# Layout (mm)
MARGIN_LEFT = 18
MARGIN_RIGHT = 12
MARGIN_TOP = 15
MARGIN_BOTTOM = 18

# Code formatting
CODE_FONT_SIZE = 8
CODE_LINE_HEIGHT = 3.6
HEADER_FONT_SIZE = 10
TITLE_FONT_SIZE = 16
SUBTITLE_FONT_SIZE = 12

# Max characters per code line before wrapping.
LINE_WRAP_LIMIT = 100


# =====================================================================
# IMPLEMENTATION
# =====================================================================


class DepositPDF(FPDF):
    def __init__(self) -> None:
        super().__init__(orientation='P', unit='mm', format='A4')
        self.set_margins(left=MARGIN_LEFT, top=MARGIN_TOP, right=MARGIN_RIGHT)
        self.set_auto_page_break(auto=True, margin=MARGIN_BOTTOM)
        self.add_font('mono', '', str(FONT_REGULAR))
        self.add_font('mono', 'B', str(FONT_BOLD))

    def footer(self) -> None:
        self.set_y(-12)
        self.set_font('mono', '', 8)
        self.set_text_color(120, 120, 120)
        self.cell(0, 5, f'Стр. {self.page_no()} из {{nb}}', align='C')
        self.set_text_color(0, 0, 0)


def check_files() -> None:
    missing = [f for f in FILES_FIRST_PART + FILES_LAST_PART if not (ROOT / f).exists()]
    if missing:
        sys.stderr.write('Missing files (check FILES_FIRST_PART / FILES_LAST_PART):\n')
        for m in missing:
            sys.stderr.write(f'  - {m}\n')
        sys.exit(1)
    if not FONT_REGULAR.exists():
        sys.stderr.write(f'Font not found: {FONT_REGULAR}\n')
        sys.stderr.write('Install Consolas or change FONT_REGULAR / FONT_BOLD.\n')
        sys.exit(1)


def wrap_line(line: str, limit: int) -> list[str]:
    """Wrap a long line at limit chars, indenting continuation chunks."""
    line = line.replace('\t', '    ').rstrip()
    if len(line) <= limit:
        return [line]
    leading = len(line) - len(line.lstrip(' '))
    indent = ' ' * (leading + 4)
    result = [line[:limit]]
    rest = line[limit:]
    chunk_size = max(20, limit - len(indent))
    while rest:
        result.append(indent + rest[:chunk_size])
        rest = rest[chunk_size:]
    return result


def render_title(pdf: DepositPDF) -> None:
    pdf.add_page()
    pdf.set_font('mono', 'B', TITLE_FONT_SIZE)
    pdf.ln(35)
    pdf.multi_cell(0, 9,
                   'ДЕПОНИРУЕМЫЙ ЭКЗЕМПЛЯР\nИСХОДНОГО ТЕКСТА ПРОГРАММЫ ДЛЯ ЭВМ',
                   align='C')
    pdf.ln(8)

    pdf.set_font('mono', 'B', SUBTITLE_FONT_SIZE)
    pdf.multi_cell(0, 6, f'«{WORK_TITLE}»', align='C')
    pdf.ln(15)

    pdf.set_font('mono', '', 10)
    info = [
        ('Тип произведения', WORK_TYPE),
        ('Версия', VERSION),
        ('Язык(и) программирования', LANGUAGES),
        ('Автор', AUTHORS),
        ('Правообладатель', RIGHTHOLDER),
        ('Год создания', str(YEAR_CREATED)),
    ]
    label_width = 70
    for label, value in info:
        pdf.cell(label_width, 6, f'{label}:', align='R')
        pdf.set_font('mono', 'B', 10)
        pdf.cell(0, 6, f'  {value}', **_NEXT)
        pdf.set_font('mono', '', 10)
    pdf.ln(10)

    pdf.multi_cell(0, 5,
                   'Состав депонируемых материалов:\n'
                   '— фрагменты исходного текста программы для ЭВМ '
                   '(начальные и завершающие модули);\n'
                   '— конфиденциальные сведения замаскированы.',
                   align='L')
    pdf.ln(15)
    pdf.cell(0, 5, f'{CITY}, {YEAR_CREATED} г.', align='C', **_NEXT)


def render_toc(pdf: DepositPDF) -> None:
    pdf.add_page()
    pdf.set_font('mono', 'B', 14)
    pdf.cell(0, 10, 'ОГЛАВЛЕНИЕ', align='C', **_NEXT)
    pdf.ln(5)

    pdf.set_font('mono', 'B', 10)
    pdf.cell(0, 6, 'Часть I. Начальные модули программы', **_NEXT)
    pdf.set_font('mono', '', 9)
    for f in FILES_FIRST_PART:
        pdf.cell(8)
        pdf.cell(0, 5, f, **_NEXT)
    pdf.ln(4)

    pdf.set_font('mono', 'B', 10)
    pdf.cell(0, 6, 'Часть II. Завершающие модули программы', **_NEXT)
    pdf.set_font('mono', '', 9)
    for f in FILES_LAST_PART:
        pdf.cell(8)
        pdf.cell(0, 5, f, **_NEXT)


def render_part_divider(pdf: DepositPDF, title: str, subtitle: str) -> None:
    pdf.add_page()
    pdf.ln(80)
    pdf.set_font('mono', 'B', 18)
    pdf.cell(0, 12, title, align='C', **_NEXT)
    pdf.ln(4)
    pdf.set_font('mono', '', 12)
    pdf.cell(0, 8, subtitle, align='C', **_NEXT)


def render_file(pdf: DepositPDF, rel_path: str) -> int:
    """Render a single source file. Returns number of source lines printed."""
    full = ROOT / rel_path
    text = full.read_text(encoding='utf-8', errors='replace')
    lines = text.splitlines()
    cap = MAX_LINES_PER_FILE.get(rel_path)
    truncated = False
    if cap is not None and len(lines) > cap:
        lines = lines[:cap]
        truncated = True

    pdf.add_page()
    pdf.set_font('mono', 'B', HEADER_FONT_SIZE)
    pdf.cell(0, 7, f'Файл: {rel_path}', **_NEXT)
    pdf.set_draw_color(160, 160, 160)
    y = pdf.get_y()
    pdf.line(MARGIN_LEFT, y, pdf.w - MARGIN_RIGHT, y)
    pdf.ln(2)

    pdf.set_font('mono', '', CODE_FONT_SIZE)
    for line_no, raw in enumerate(lines, start=1):
        chunks = wrap_line(sanitize(raw), LINE_WRAP_LIMIT)
        for i, chunk in enumerate(chunks):
            prefix = f'{line_no:4d}  ' if i == 0 else '      '
            pdf.cell(0, CODE_LINE_HEIGHT, prefix + chunk, **_NEXT)

    if truncated:
        pdf.ln(2)
        pdf.set_font('mono', 'B', CODE_FONT_SIZE)
        pdf.cell(0, CODE_LINE_HEIGHT,
                 f'[ ... фрагмент сокращён, всего в файле {len(text.splitlines())} строк(и) ... ]',
                 **_NEXT)
    return len(lines)


def main() -> None:
    check_files()
    pdf = DepositPDF()

    render_title(pdf)
    render_toc(pdf)

    render_part_divider(pdf, 'ЧАСТЬ I', 'Начальные модули программы')
    total_lines = 0
    for f in FILES_FIRST_PART:
        total_lines += render_file(pdf, f)

    render_part_divider(pdf, 'ЧАСТЬ II', 'Завершающие модули программы')
    for f in FILES_LAST_PART:
        total_lines += render_file(pdf, f)

    pdf.output(str(OUTPUT))

    print(f'Файл создан: {OUTPUT}')
    print(f'Страниц всего: {pdf.page_no()}')
    print(f'Строк исходного кода в депозите: {total_lines}')
    if pdf.page_no() < 30:
        print('  → объём маловат для депозита, добавь файлы в FILES_LAST_PART.')
    elif pdf.page_no() > 80:
        print('  → объём большой, можно урезать через MAX_LINES_PER_FILE.')


if __name__ == '__main__':
    main()
