# would have been much nicer with 3.6 f-strings but that's not
# yet available on faraday that runs ubuntu-16.04

from datetime import datetime
import smtplib


def font_color_tick(column, failed_column):
    "return a couple of style and content for a span element" 

    return (
        # all is fine, show a green dot
        ('32px Arial, Tahoma, Sans-serif' , '#42c944' , '&#8226;') if column < failed_column 
        # otherwise, a red cross
        else ('18px Arial, Tahoma, Sans-serif',  'red', '&#215;') if column == failed_column
        else ('18px Arial, Tahoma, Sans-serif',  'gray', '&#65110;'))


def summary_table(failures):
    """
    based on the failures structure 
    that maps node ids to a failure reason
    produce a summary mail
    """

    header = """<tr>
<td style="width: 40px; text-align: center;">
 <h5><span style="background:#f0ad4e; color:#fff; padding:4px; border-radius: 5px;">[DATE]
 </span></h5></td>
<td style="font:11px Arial, Tahoma, Sans-serif; width: 40px; text-align: center;">
 <img src="http://r2lab.inria.fr/assets/img/nightly-power.png" style="width:25px;height:25px;" />&nbsp;start&nbsp;</td>
<td style="font:11px Arial, Tahoma, Sans-serif; width: 40px; text-align: center;">
 <img src="http://r2lab.inria.fr/assets/img/nightly-share.png" style="width:25px;height:25px;" />load</td>
<td style="font:11px Arial, Tahoma, Sans-serif; width: 40px; text-align: center;">
 <img src="http://r2lab.inria.fr/assets/img/nightly-zombie.png" style="width:25px;height:25px;" />zombie</td>
<td>&nbsp;&nbsp;</td>
</tr>"""

    result = header
    for id in sorted(failures):
        reason = failures[id]
        # the node id badge
        line = """<tr>
<td style="font:15px helveticaneue, Arial, Tahoma, Sans-serif;">
 <span style="border-radius: 50%; border: 2px solid #525252; width: 30px; height: 30px; line-height: 30px; display: block; text-align: center;">
  <span style="color: #525252;">{}
</span></span></td>""".format(id)
        # which column whould be outlined
        failed_column = reason.mail_column()
        for column in range(3):
            font, color, tick = font_color_tick(column, failed_column)
            line += '<td style="text-align: center; font:{font}; color:{color}">{tick}</td>'.format(**locals())
        line += "</tr>"
        result += line
    return result


def dummy_html():
    body = '''<!DOCTYPE html><html lang="en">
<head>
 <meta charset="utf-8">
 <meta http-equiv="X-UA-Compatible" content="IE=edge">
</head>
<body style="font:14px helveticaneue, Arial, Tahoma, Sans-serif; margin: 0;">
 <table style="padding: 10px;">
  [CONTENTS]
 </table>
</body>
</html>'''
    return body


# entry points of interest start here
def complete_html(failures):
    now = datetime.now()
    today = now.strftime("%d/%m/%Y")
    template = dummy_html()
    html = template.replace("[CONTENTS]",
                            summary_table(failures))\
                   .replace("[DATE]",
                            today)
    return html


def send_email(sender, receiver, subject, content):
    """ send email using python """
    from email.mime.multipart import MIMEMultipart
    from email.mime.text import MIMEText

    # Create message container - the correct MIME type is multipart/alternative.
    msg = MIMEMultipart('alternative')
    msg['Subject']  = subject
    msg['From']     = sender
    msg['To']       = ", ".join(receiver)

    # Record the MIME types of both parts - text/plain and text/html.
    body = MIMEText(content, 'html')

    # Attach parts into message container.
    # According to RFC 2046, the last part of a multipart message, in this case
    # the HTML message, is best and preferred.
    msg.attach(body)

    # Send the message via local SMTP server.
    s = smtplib.SMTP('localhost')
    # sendmail function takes 3 arguments: sender's address, recipient's address
    # and message to send - here it is sent as one string.
    s.sendmail(sender, receiver, msg.as_string())
    s.quit()







if __name__ == '__main__':

    from nightly import Reason

    fake_failures = {
        30 : Reason.WONT_TURN_ON,
        31 : Reason.WONT_SSH,
        37 : Reason.DID_NOT_LOAD,
    }
    with open('foo.html', 'w') as output:
        output.write(complete_html(fake_failures))
    print('see foo.html')
