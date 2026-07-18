using System.ComponentModel;
namespace Rolf {
    public class ProfileItem : INotifyPropertyChanged {
        public event PropertyChangedEventHandler PropertyChanged;
        private bool _isSelected;
        public bool IsSelected {
            get { return _isSelected; }
            set { if (_isSelected != value) { _isSelected = value; OnChanged("IsSelected"); } }
        }
        public string UserName     { get; set; }
        public string Sid          { get; set; }
        public string LocalPath    { get; set; }
        public string LastUseTime  { get; set; }
        public int    InactiveDays { get; set; }
        public bool   Loaded       { get; set; }
        public bool   Special      { get; set; }
        public bool   Protected    { get; set; }
        public bool   Inactive     { get; set; }
        public string SizeText     { get; set; }
        public double SizeBytes    { get; set; }
        private void OnChanged(string p) {
            var h = PropertyChanged;
            if (h != null) { h(this, new PropertyChangedEventArgs(p)); }
        }
    }
}
