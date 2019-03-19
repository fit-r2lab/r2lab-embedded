"""
helper functions to prepare and send a summary mail once nightly is done
"""

from datetime import datetime
import smtplib


def font_color_tick(column, failed_column):
    "return a couple of style and content for a span element"

    return (
        # all is fine, show a green dot
        ('32px Arial, Tahoma, Sans-serif', '#42c944', '&#8226;')
        if column < failed_column
        # otherwise, a red cross
        else ('18px Arial, Tahoma, Sans-serif', 'red', '&#215;')
        if column == failed_column
        else ('18px Arial, Tahoma, Sans-serif', 'gray', '&#65110;'))


def header_line(nodenames, failures):
    """
    Returns a HTML fragment with an overview of the results
    """
    return (f"<p>On [DATE]"
            f"<br/>Report on {len(nodenames)} nodes"
            f"<br/>Detected {len(failures)} issues.</p>")

def summary_table(nodenames, failures):
    """
    based on the failures structure that maps node ids to a failure reason
    produce a table where eavh failed node is attached a failure reason
    """

    if not failures:
        return f"<p>All {len(nodenames)} nodes were found to be fine.</p>"

    header = """<tr>
<td style="width: 40px; text-align: center;">
 <h5><span style="background:#f0ad4e; color:#fff; padding:4px; border-radius: 5px;">[DATE]
 </span></h5></td>
<td style="font:11px Arial, Tahoma, Sans-serif; width: 40px; text-align: center;">
 <img src="http://r2lab.inria.fr/assets/img/nightly-power.png"
  style="width:25px;height:25px;" />&nbsp;start&nbsp;</td>
<td style="font:11px Arial, Tahoma, Sans-serif; width: 40px; text-align: center;">
 <img src="http://r2lab.inria.fr/assets/img/nightly-share.png"
 style="width:25px;height:25px;" />load</td>
<td style="font:11px Arial, Tahoma, Sans-serif; width: 40px; text-align: center;">
 <img src="http://r2lab.inria.fr/assets/img/nightly-zombie.png"
 style="width:25px;height:25px;" />zombie</td>
<td>&nbsp;&nbsp;</td>
</tr>"""

    result = header
    for node_id in sorted(failures):
        reason = failures[node_id]
        # the node id badge
        line = f"""<tr>
<td><span class="foo"><span class="bar">{node_id}</span></span></td>"""
        # which column should be outlined
        failed_column = reason.mail_column()
        for column in range(3):
            font, color, tick = font_color_tick(column, failed_column)
            line += f"""<td style="text-align: center; font:{font}; color:{color}">{tick}</td>"""
        line += "</tr>"
        result += line
    return result


def html_skeleton():
    """
    The skeleton for the summary mail
    """
    body = '''<!DOCTYPE html><html lang="en">
<head>
 <meta charset="utf-8">
 <meta http-equiv="X-UA-Compatible" content="IE=edge">
 <style>
td {
    font:15px helveticaneue, Arial, Tahoma, Sans-serif;
}
td>span.foo {
    border-radius: 50%;
    border: 2px solid #525252;
    width: 30px;
    height: 30px;
    line-height: 30px;
    display: block;
    text-align: center;
}
td>span.bar {
    color: #525252;
}
 </style>
</head>
<body style="font:14px helveticaneue, Arial, Tahoma, Sans-serif; margin: 0;">
[HEADER]
 <table style="padding: 10px;">
  [TABLE]
 </table>
</body>
</html>'''
    return body


# entry points of interest start here
def complete_html(nodenames, failures):
    """
    The main entry point to the outside
    Put it all together and create the mail body
    """
    now = datetime.now()
    today = now.strftime("%d/%m/%Y")
    template = html_skeleton()
    html = (template
            .replace("[HEADER]",
                     header_line(nodenames, failures))
            .replace("[TABLE]",
                     summary_table(nodenames, failures))
            .replace("[DATE]",
                     today))
    return html


def send_email(sender, receiver, subject, content):
    """
    actually send email
    """
    from email.mime.multipart import MIMEMultipart
    from email.mime.text import MIMEText

    # Create message container - the correct MIME type is multipart/alternative.
    msg = MIMEMultipart('alternative')
    msg['Subject'] = subject                            # pylint: disable=c0326
    msg['From']    = sender                             # pylint: disable=c0326
    if isinstance(receiver, str):
        msg['To']  = receiver                           # pylint: disable=c0326
    else:
        msg['To']  = ", ".join(receiver)                # pylint: disable=c0326

    # Record the MIME types of both parts - text/plain and text/html.
    body = MIMEText(content, 'html')

    # Attach parts into message container.
    # According to RFC 2046, the last part of a multipart message, in this case
    # the HTML message, is best and preferred.
    msg.attach(body)

    # Send the message via local SMTP server.
    with smtplib.SMTP('localhost') as mailer:
        # sendmail function takes 3 arguments:
        # sender's address, recipient's address
        # and message to send - here it is sent as one string.
        mailer.sendmail(sender, receiver, msg.as_string())
        # I take it this is taken care of by context manager
        # mailer.quit()


def main():
    """
    manual unit test
    """

    from nightly import Reason

    fake_failures = {
        30 : Reason.WONT_TURN_ON,
        31 : Reason.WONT_SSH,
        37 : Reason.DID_NOT_LOAD,
    }
    fake_nodenames = [f'fit{x:02d}' for x in range(1, 11)]
    with open('foo.html', 'w') as output:
        output.write(complete_html(
            fake_nodenames, fake_failures))
    print('see foo.html')


if __name__ == '__main__':
    main()
