package DBIx::Class::Helper::Schema::ERD;

use warnings;
use strict;
use autodie;

use base qw/DBIx::Class::Schema/;

use Time::HiRes qw/sleep/;
use File::Temp;
use POSIX();

my $pagesize = {
  # pagesizes in inches
  a4 => { w => 842/72, h => 595/72 },
  a0 => { w => 3370/72, h => 2384/72 },
};
my $page = 'a4';

sub __parse_pagesize {
  my $args = { (ref $_[0] eq 'HASH') ? %{$_[0]} : @_ };

  if ($args->{paginate}) {
    $args->{pagewidth} ||= $pagesize->{$page}{w},
    $args->{pageheight} ||= $pagesize->{$page}{h},
  }

  # otherwise graphviz decides to be smart and renders multiple pages
  # think of this as margins
  my $reduce_height = 0.85;
  my $reduce_width = 0.90;

  $args->{width} ||= ($args->{span_wide} || 1) * ($args->{pagewidth} || $pagesize->{$page}{w}) * $reduce_width;
  $args->{height} ||= ($args->{span_high} || 1) * ($args->{pageheight} || $pagesize->{$page}{h}) * $reduce_height;

  $args;
}

sub erd_render {
  my $self = shift;
  my $args = { (ref $_[0] eq 'HASH') ? %{$_[0]} : @_ };

  # set defaults
  $args = {
    show_fields => 1,
    show_constraints => 1,
    show_datatypes => 1,
    show_sizes => 1,

    output_type => 'ps',
    fontsize => 8,
    fontname => 'Courier bold',

    %{__parse_pagesize($args)},
  };

  unless ($args->{out_file}) {
    $args->{out_file} = File::Temp->new (TEMPLATE => CCS->tmpdir->file ('dbic_erd_XXXXX') );
    close ($args->{out_file});
  }

  require SQL::Translator;
  my $trans = SQL::Translator->new (
    parser => 'SQL::Translator::Parser::DBIx::Class',
    parser_args => { package => $self, %{$args->{dbic_parser_args}||{}} },
    producer => 'GraphViz',
    producer_args => $args,
  ) or $self->throw_exception (SQL::Translator->error);
  $trans->translate or $self->throw_exception ($trans->error);

  return $args->{out_file};
}

sub erd_print {
  my $self = shift;
  my $args = { (ref $_[0] eq 'HASH') ? %{$_[0]} : @_ };

  my $pdf_fn = File::Temp->new (TEMPLATE => CCS->tmpdir->file ('dbic_erd_XXXXX'));

  my ($pw, $ph) = @{__parse_pagesize($args)}{qw/pagewidth pageheight/};
  __ps_to_pdf (
    "$pdf_fn",
    $pw || $pagesize->{$page}{w},
    $ph || $pagesize->{$page}{h},
    $self->erd_render ($args),
  );
  system (qw/lpr/, $pdf_fn);
  sleep 1;
}

sub erd_view {
  my $self = shift;

  # we fork for the viewer and create the tempfile within the child
  # this allows for proper cleanup
  my $pid = fork();
  if ($pid) {
    # the parent is done after giving time for SIG{CHLD} override
    sleep 0.2;
    return;
  }
  else {
    $SIG{CHLD} = 'IGNORE';  # don't care about the parent

    # try to kill old viewer
    my $pidfile = CCS->tmpdir->file ('erdviewer.pid');
    if (-f $pidfile) {
      my ($oldpid) = $pidfile->slurp =~ /^(\d+)\n/;
      kill (- POSIX::SIGTERM, $oldpid) if $oldpid;    # negative for entire process group
    }

    my $erdfile = $self->erd_render (@_);
    $SIG{TERM} = sub { _viewer_cleanup ($pidfile, $erdfile) };

    my $pidfh = $pidfile->openw;
    print $pidfh "$$\n";
    close ($pidfh);

    # not an exec so the temp file removal takes place once the viewer is closed
    setpgrp (0,0);  #make process group leader so -TERM will work
    close STDERR;
    open *STDERR, '>', '/dev/null';
    system ('evince', '--class=DBIC_ERD', $erdfile);
    _viewer_cleanup ($pidfile, $erdfile);
  }
}

sub _viewer_cleanup {
  for (@_) {
    unlink ($_) if -f $_;
  }
  exit 0;
}

sub erd_pdf {
  my $self = shift;
  my $args = { (ref $_[0] eq 'HASH') ? %{$_[0]} : @_ };

  my ($pw, $ph) = @{__parse_pagesize($args)}{qw/pagewidth pageheight/};
  __ps_to_pdf (
    CCS->tmpdir->file ('ERD.pdf'),
    $pw || $pagesize->{$page}{w},
    $ph || $pagesize->{$page}{h},
    $self->erd_render (paginate => 1, %$args),
    $self->erd_render (paginate => 1, %$args, show_fields => 0 ),
  );
}

sub __ps_to_pdf {
  my ($pdf_fn, $page_width, $page_height, @ps_files) = @_;

  my $gs_pagesize = join (' ', map { int ($_ * 72) }
    $page_width,
    $page_height,
  );

  # ps to pdf is a bitch. Some references:
  # http://www.troubleshooters.com/linux/gs.htm#_Making_a_Landscape_PDF
  # http://ghostscript.com/doc/current/Use.htm#Known_paper_sizes
  system ('gs', qw/-dQUIET -dBATCH -dNOPAUSE -sDEVICE=pdfwrite/,
    "-sOutputFile=$pdf_fn",
    '-c', "<</PageSize [$gs_pagesize]>> setpagedevice", '-f',
    @ps_files,
  )
}

1;
