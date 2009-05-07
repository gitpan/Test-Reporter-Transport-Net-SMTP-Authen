use strict;
use warnings;
package Test::Reporter::Transport::Net::SMTP::Authen;
use base 'Test::Reporter::Transport::Net::SMTP';
use vars qw/$VERSION/;
$VERSION = '1.00';
$VERSION = eval $VERSION;

sub new {
    my ($class, @args) = @_;
    bless { args => \@args } => $class;
}

sub _net_class {
    my ($self) = @_;
    my $class = ref $self ? ref $self : $self;
    my ($net_class) = ($class =~ /^Test::Reporter::Transport::(.+)\z/);
	return 'Net::SMTP' if $net_class eq 'Net::SMTP::Authen';
    return $net_class;
}

sub _perform_auth{
    my $self = shift;
    my $transport = shift;
    my $args = $$self{args};
    my %opts = ( @$args );
    
    my ($user_name) = $opts{'User'} || $opts{'Username'};
    my ($password) = $opts{'Password'} || $opts{'Pass'};
    die "No user_name" unless $user_name;
    return 1 if ($self->_net_class() eq 'Net::SMTP::TLS');
    return $transport->auth($user_name, $password);		
}


sub send {
    my ($self, $report, $recipients) = @_;
    $recipients ||= [];

    my $helo          = $report->_maildomain(); # XXX: tight -- rjbs, 2008-04-06
    my $from          = $report->from();
    my $via           = $report->via();
    my @tmprecipients = ();
    my @bad           = ();
    my $smtp;

    my $mx;

    my $transport = $self->_net_class;

    # Sorry.  Tight coupling happened before I got here. -- rjbs, 2008-04-06
    for my $server (@{$report->{_mx}}) {
        eval {
            $smtp = $transport->new(
                $server,
                Hello   => $helo,
                Timeout => $report->timeout(),
                Debug   => $report->debug(),
                $report->transport_args(),
            );
        };

        if (defined $smtp) {
            $mx = $server;
            last;
        }
    }

    die "Unable to connect to any MX's: $@" unless $mx && $smtp;

    my $cc_str;
    if (@$recipients) {
        if ($mx =~ /(?:^|\.)(?:perl|cpan)\.org$/) {
            for my $recipient (sort @$recipients) {
                if ($recipient =~ /(?:@|\.)(?:perl|cpan)\.org$/) {
                    push @tmprecipients, $recipient;
                } else {
                    push @bad, $recipient;
                }
            }

            if (@bad) {
                warn __PACKAGE__, ": Will not attempt to cc the following recipients since perl.org MX's will not relay for them. Either use Test::Reporter::Transport::Mail::Send, use other MX's, or only cc address ending in cpan.org or perl.org: ${\(join ', ', @bad)}.\n";
            }

            $recipients = \@tmprecipients;
        }

        $cc_str = join ', ', @$recipients;
        chomp $cc_str;
        chomp $cc_str;
    }

    $via = ', via ' . $via if $via;

    my $envelope_sender = $from;
    $envelope_sender =~ s/\s\([^)]+\)$//; # email only; no name

    # Net::SMTP returns 1 or undef for pass/fail 
    # Net::SMTP::TLS croaks on fail but may not return 1 on pass
    # so this closure lets us die on an undef return only for Net::SMTP
    my $die = sub { die $smtp->message if ref $smtp eq 'Net::SMTP' };
    

    eval {
	trace(1);
	$self->_perform_auth($smtp) or $die->();
	trace();
		
        $smtp->mail($envelope_sender) or $die->();
	trace();
        $smtp->to($report->address) or $die->();
	trace();
        if ( @$recipients ) { $smtp->cc(@$recipients) or $die->() };
	trace();
        $smtp->data() or $die->();
	trace();
        $smtp->datasend("Date: ", $self->_format_date, "\n") or $die->();
	trace();
        $smtp->datasend("Subject: ", $report->subject, "\n") or $die->();
	trace();
        $smtp->datasend("From: $from\n") or $die->();
	trace();
        $smtp->datasend("To: ", $report->address, "\n") or $die->();
	trace();
        if ( @$recipients ) { $smtp->datasend("Cc: $cc_str\n") or $die->() };
	trace();
        $smtp->datasend("Message-ID: ", $report->message_id(), "\n") or $die->();
	trace();
        $smtp->datasend("X-Reported-Via: Test::Reporter $Test::Reporter::VERSION$via\n") or $die->();
	trace();
        $smtp->datasend("\n") or $die->();
	trace();
	trace();
        $smtp->datasend($report->report()) or $die->();
	trace();
        $smtp->dataend() or $die->();
	trace();
	print STDERR "Data end\n";
        $smtp->quit or $die->();
	trace();
        1;
    } or die "$transport - $@";

    return 1;
}

1;

sub trace{
    my $mess = shift;
    my ($package, $file, $line, $func) = caller 1;
    my ($package1, $file1, $line1, $func1) = caller 0;
    #print STDERR "[$line:$line1] "; 
}
    
__END__

=head1 NAME

Test::Reporter::Transport::Net::SMTP::Authen - SMTP transport for Test::Reporter 
WITH AUTH command

=head1 SYNOPSIS

    my $report = Test::Reporter->new(
        transport => 'Net::SMTP::Authen',
        transport_args => [ User => 'John', Password => '123' ],
    );

=head1 DESCRIPTION

This module transmits a Test::Reporter report using Net::SMTP with authentication if needed.

=head1 USAGE

See L<Test::Reporter> and L<Test::Reporter::Transport> for general usage
information.

Net::SMTP::Authen

=head2 Transport Arguments

    $report->transport_args( @args );

Any transport arguments are passed through to the Net::SMTP constructer.

=head1 METHODS

These methods are only for internal use by Test::Reporter.

=head2 new

    my $sender = Test::Reporter::Transport::Net::SMTP->new( @args );
    
The C<new> method is the object constructor.   

=head2 send

    $sender->send( $report );

The C<send> method transmits the report.  

=head1 AUTHOR

=over

=item *

David A. Golden (DAGOLDEN)

=item *

Ricardo Signes (RJBS)

=item *

Anatoliy Grishaev(GRIAN)

=back

=head1 COPYRIGHT

 Copyright (C) 2002, 2003, 2004, 2005, 2006, 2007, 2008 Adam J. Foxson.
 Copyright (C) 2004, 2005 Richard Soderberg.
 Copyright (C) 2008 David A. Golden
 Copyright (C) 2008 Ricardo Signes

 All rights reserved.

=head1 LICENSE

This program is free software; you may redistribute it
and/or modify it under the same terms as Perl itself.

=cut

