from pathlib import Path
import random
import subprocess
from PIL import Image, ImageEnhance, ImageFilter
from reportlab.lib import colors
from reportlab.lib.pagesizes import A4
from reportlab.lib.styles import getSampleStyleSheet, ParagraphStyle
from reportlab.lib.units import mm
from reportlab.platypus import SimpleDocTemplate, Table, TableStyle, Paragraph, Spacer, PageBreak

ROOT = Path('/Users/pro-3ies/Documents/projects/report_wise')
TMP = ROOT / 'tmp/pdfs'
OUT = ROOT / 'output/pdf'
TMP.mkdir(parents=True, exist_ok=True)
OUT.mkdir(parents=True, exist_ok=True)
source = TMP / 'sample_register_source.pdf'
final = OUT / 'sample_school_student_register_scanned.pdf'

styles = getSampleStyleSheet()
styles.add(ParagraphStyle(name='School', fontName='Helvetica-Bold', fontSize=15, leading=18, alignment=1, textColor=colors.HexColor('#173d31')))
styles.add(ParagraphStyle(name='Sub', fontName='Helvetica', fontSize=8.5, leading=11, alignment=1, textColor=colors.HexColor('#444444')))
styles.add(ParagraphStyle(name='Note', fontName='Helvetica', fontSize=7.5, leading=10, textColor=colors.HexColor('#555555')))
styles.add(ParagraphStyle(name='Cell', fontName='Helvetica', fontSize=7.4, leading=8.5))
styles.add(ParagraphStyle(name='Head', fontName='Helvetica', fontSize=7.2, leading=8, textColor=colors.white))

pages = [
    ('FORM 1 REGISTER - 2026/2027', ['No.', 'Admission No.', 'Student Name', 'Date of Birth', 'Sex', 'Class'], [
        ['1', 'ADM-26001', 'Amina Bello', '12/03/2012', 'F', 'Form 1A'], ['2', 'ADM-26002', 'Blaise Mballa', '2012-09-18', 'M', 'Form 1A'],
        ['3', 'ADM-26003', 'Chantal Ngozi', '07-11-2013', 'F', 'Form 1A'], ['4', '', 'David Tamba', '21/01/2012', 'M', 'Form 1A'],
        ['5', 'ADM-26005', 'Esther Njoya', '', 'F', 'Form 1A'], ['6', 'ADM-26006', 'Fabrice Kenne', '30/06/2012', 'M', 'Form 1B'],
        ['7', 'ADM-26007', 'Grace Atabong', '14/08/2013', 'F', 'Form 1B'], ['8', 'ADM-26008', 'Hassan Abdou', '09/10/2012', 'M', 'Form 1B'],
        ['9', 'ADM-26009', 'Irene Fombad', '2013-02-02', 'F', 'Form 1B'], ['10', 'ADM-26010', 'Joel Nsom', '18/12/2012', 'M', 'Form 1B'],
    ]),
    ('LISTE DES ELEVES - 5EME', ['Matricule', 'Full Name', 'DOB', 'Gender', 'Level', 'Guardian phone'], [
        ['MAT-5-001', 'Khadija Issa', '04/04/2011', 'F', '5eme A', '677 100 201'], ['MAT-5-002', 'Louis Etoundi', '2011-05-16', 'M', '5eme A', '699 204 118'],
        ['MAT-5-003', 'Madeleine Abena', '22/07/2011', 'F', '5eme A', '650 880 441'], ['', 'Nadia Ojong', '03/09/2011', 'F', '5eme A', ''],
        ['MAT-5-005', 'Olivier Tchana', '11/01/2011', 'M', '5eme B', '677 320 902'], ['MAT-5-006', 'Pauline Etoa', '2011-03-27', 'F', '5eme B', '699 721 003'],
        ['MAT-5-007', 'Quentin Mvondo', '06/06/2011', 'M', '5eme B', '650 111 847'], ['MAT-5-008', 'Rebecca Sama', '29/10/2011', 'F', '5eme B', '677 998 230'],
        ['MAT-5-009', 'Samuel Neba', '08/12/2011', 'M', '5eme B', '699 309 441'], ['MAT-5-010', 'Therese Ngassa', '15/02/2011', 'F', '5eme B', '650 443 701'],
    ]),
    ('STUDENT ENROLMENT SHEET - 3EME', ['N°', 'First name', 'Last name', 'Student ID', 'Level', 'Sex', 'Birth date'], [
        ['1', 'Ursula', 'Ateba', 'ST-3001', '3eme A', 'F', '17/05/2009'], ['2', 'Victor', 'Bikong', 'ST-3002', '3eme A', 'M', '2009-09-21'],
        ['3', 'William', 'Dika', '', '3eme A', 'M', '02/02/2010'], ['4', 'Xavier', 'Ewane', 'ST-3004', '3eme A', 'M', '19/11/2009'],
        ['5', 'Yvette', 'Fouda', 'ST-3005', '3eme B', 'F', '08/01/2010'], ['6', 'Zacharie', 'Nana', 'ST-3006', '3eme B', 'M', '13/03/2009'],
        ['7', 'Adeline', 'Onana', 'ST-3007', '3eme B', 'F', '27/06/2009'], ['8', 'Brice', 'Toko', 'ST-3008', '3eme B', 'M', '31/08/2009'],
        ['9', 'Carine', 'Wamba', 'ST-3009', '3eme B', 'F', '2010-04-12'], ['10', 'Doris', 'Yondo', 'ST-3010', '3eme B', 'F', '05/10/2009'],
    ]),
]

def footer(canvas, doc):
    canvas.saveState(); canvas.setStrokeColor(colors.HexColor('#9aa89f')); canvas.line(18 * mm, 15 * mm, 192 * mm, 15 * mm)
    canvas.setFont('Helvetica', 7); canvas.setFillColor(colors.HexColor('#6f766f'))
    canvas.drawString(18 * mm, 10 * mm, 'Synthetic test document - no real student data')
    canvas.drawRightString(192 * mm, 10 * mm, f'Page {doc.page}'); canvas.restoreState()

doc = SimpleDocTemplate(str(source), pagesize=A4, rightMargin=15 * mm, leftMargin=15 * mm, topMargin=13 * mm, bottomMargin=22 * mm)
story = []
for index, (title, headers, rows) in enumerate(pages):
    story += [Paragraph('GOVERNMENT BILINGUAL HIGH SCHOOL - YAOUNDE', styles['School']), Paragraph('Academic year 2026/2027 | Student registry sample', styles['Sub']), Spacer(1, 4 * mm), Paragraph(title, styles['Sub']), Spacer(1, 3 * mm)]
    widths = [14, 29, 43, 28, 18, 28, 28] if len(headers) == 7 else [14, 32, 48, 30, 18, 30]
    table_data = [[Paragraph(str(value), styles['Head']) for value in headers]]
    table_data += [[Paragraph(str(value), styles['Cell']) for value in row] for row in rows]
    table = Table(table_data, colWidths=[w * mm for w in widths], repeatRows=1)
    table.setStyle(TableStyle([('BACKGROUND', (0, 0), (-1, 0), colors.HexColor('#245746')), ('TEXTCOLOR', (0, 0), (-1, 0), colors.white), ('FONTNAME', (0, 0), (-1, -1), 'Helvetica'), ('FONTSIZE', (0, 0), (-1, 0), 7.4), ('FONTSIZE', (0, 1), (-1, -1), 7.8), ('GRID', (0, 0), (-1, -1), .35, colors.HexColor('#89998e')), ('ROWBACKGROUNDS', (0, 1), (-1, -1), [colors.white, colors.HexColor('#f1f5f1')]), ('VALIGN', (0, 0), (-1, -1), 'MIDDLE'), ('TOPPADDING', (0, 0), (-1, -1), 5), ('BOTTOMPADDING', (0, 0), (-1, -1), 5)]))
    story += [table, Spacer(1, 7 * mm), Paragraph('Registrar note: blank identifiers and mixed date formats are intentional test cases for review.', styles['Note'])]
    if index < len(pages) - 1: story.append(PageBreak())
doc.build(story, onFirstPage=footer, onLaterPages=footer)

subprocess.run(['pdftoppm', '-r', '160', '-png', str(source), str(TMP / 'sample_register_page')], check=True)
images = []; random.seed(7)
for path in sorted(TMP.glob('sample_register_page-*.png')):
    image = ImageEnhance.Contrast(Image.open(path).convert('L')).enhance(.9).filter(ImageFilter.GaussianBlur(.12))
    pixels = image.load()
    for _ in range(2500):
        x, y = random.randrange(image.width), random.randrange(image.height); pixels[x, y] = max(0, min(255, pixels[x, y] + random.choice([-3, -2, 2, 3])))
    images.append(image.convert('RGB'))
images[0].save(final, save_all=True, append_images=images[1:], resolution=160.0)
print(final)
